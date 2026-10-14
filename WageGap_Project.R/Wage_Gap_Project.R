# ==========================================================================
# Wage Gap between Vocational/Trades and University-Educated Workers, US
# Pooled cross-section analysis using ACS microdata (IPUMS USA), 2010-2024
# ==========================================================================
#
#
## AI NOTE: 
#
# Claude AI is partially used in this script and data processing in the 
# following ways:
# The original microdataset is under usa_00001.dat 3, Claude is used to 
# restructure this data set into acs_2010_2024_slim.csv in order to put data
# into a cleaner setup and also reduces its capacity requirements.
# Claude is used in the variable construction due to the vastness of the dataset
# it ensure I myself do not misclassify certain variables when viewing over the
# data and writing in the code myself.
# Claude is used in the debt-adjustment section in section 9, since I was not 
# familiar with the financial data tools in R studio.
#
#
## 0. Setup -------------------------------------------------------------------

# install.packages(c("data.table","dplyr","tidyr","ggplot2","fixest","broom","modelsummary"))
library(data.table)   # fread: much faster and more memory-efficient than
# read_csv/read_fwf for a multi-million-row file --
# important given limited (8GB) RAM
library(dplyr)
library(tidyr)
library(ggplot2)
library(fixest)
library(broom)
library(modelsummary)

dir.create("output", showWarnings = FALSE)

## 1. Load the extract -----------------------------------------------------------
# Loading the slimmed-down CSV, which keeps only the 12 columns actually used
# below (year, serial, perwt, sex, age, educd, empstat, ind, wkswork2,
# uhrswork, incwage, incwage_cpiu_2010) -- the full 27-column extract carried
# several unused technical/variance-estimation columns (cbserial, cluster,
# strata, degfield/degfieldd/degfield2/degfield2d, empstatd, qearn, qincwage,
# hhwt, general educ) that were never referenced anywhere in this script, so
# dropping them roughly halves the memory footprint for no analytical cost.

acs_raw <- fread("data/acs_2010_2024_slim.csv") %>% as_tibble()

cat("Rows loaded:", nrow(acs_raw), "\n")
cat("Years present:", paste(sort(unique(acs_raw$year)), collapse = ", "), "\n")

## 2. Restrict to the study period ----------------------------------------------
# Defensive filter -- the CSV should already be limited to 2010-2024, but this
# guards against accidentally pointing the script at an unfiltered extract.

acs <- acs_raw %>% filter(year >= 2010, year <= 2024)

cat("Rows after year filter:", nrow(acs), "\n")

## 3. Variable construction ------------------------------------------------------

acs <- acs %>%
  mutate(
    # Implied decimal: PERWT is stored as an integer with 2 implied decimal
    # places (e.g. raw 010461 means 104.61). HHWT was dropped from the slim
    # extract since it's a household-level weight not used anywhere below --
    # this analysis is person-level throughout, using PERWT.
    perwt = perwt / 100,
    
    female = if_else(sex == 2, 1, 0),                     # 1 = Male, 2 = Female
    age    = if_else(age == 999, NA_real_, age),           # 999 = missing
    
    # WKSWORK2 is bucketed, not exact -- convert to an approximate midpoint.
    # This is a stated approximation, not exact weeks worked.
    weeks_worked = case_when(
      wkswork2 == 1 ~ 7,     # 1-13 weeks
      wkswork2 == 2 ~ 20,    # 14-26 weeks
      wkswork2 == 3 ~ 33,    # 27-39 weeks
      wkswork2 == 4 ~ 44,    # 40-47 weeks
      wkswork2 == 5 ~ 48.5,  # 48-49 weeks
      wkswork2 == 6 ~ 51,    # 50-52 weeks
      TRUE          ~ NA_real_   # 0 = N/A
    ),
    
    # INCWAGE missing/NA sentinel codes (per DDI): 999999 = N/A, 999998 = Missing
    incwage_valid = !(incwage %in% c(999999, 999998)),
    
    # Real (2010 dollars) hourly wage, using the pre-adjusted CPI variable
    annual_hours = uhrswork * weeks_worked,
    hourly_wage  = if_else(incwage_valid & annual_hours > 0,
                           incwage_cpiu_2010 / annual_hours, NA_real_),
    log_wage     = log(hourly_wage)
  )

# --- Education classification --------------------------------------------------
# EDUCD codes confirmed from the DDI codebook, for 2010-2024 specifically:
#   101 = Bachelor's degree, 114 = Master's, 115 = Professional, 116 = Doctoral
#   81  = Associate's degree (type not specified -- the occupational/academic
#         split, codes 82/83, is NOT populated for 2010-2024, only for 1990)
#
# "Vocational" is broadened beyond the Associate's-degree credential to also
# capture people currently working in a trades industry (construction,
# electrical, etc.), per the earlier scoping discussion -- credential takes
# priority, so nobody with a Bachelor's+ degree gets reclassified as
# vocational just because of their current industry.
#
# IND code confirmed directly from IPUMS's industry code documentation:
#   770 = "Construction, including cleaning during and immediately after"
# This is a broad industry-sector code -- it includes everyone from laborers
# to site managers to admin staff working in construction, not only tradespeople
# specifically (see the OCC-vs-IND precision caveat discussed earlier). It is
# also one of the most common codes in this dataset (~150k of 4.08M rows).
trades_ind_codes <- c(770)

acs <- acs %>%
  mutate(
    university = if_else(educd %in% c(101, 114, 115, 116), 1, 0),
    vocational = if_else(university == 0 &
                           (educd == 81 | ind %in% trades_ind_codes),
                         1, 0),
    educ_group = case_when(
      university == 1 ~ "university",
      vocational == 1 ~ "vocational",
      TRUE             ~ NA_character_   # the ambiguous middle -- dropped
    )
  )

## 4. Sample selection -----------------------------------------------------------

sample <- acs %>%
  filter(
    age >= 25, age <= 64,
    empstat == 1,                 # employed
    !is.na(educ_group),
    !is.na(hourly_wage), is.finite(log_wage)
  )

cat("Final analytic sample size:", nrow(sample), "person-year observations\n")

## 5. Descriptive statistics and plots --------------------------------------------

comp_table <- sample %>%
  group_by(year, educ_group) %>%
  summarise(n = n(), .groups = "drop") %>%
  pivot_wider(names_from = educ_group, values_from = n)
print(comp_table)
write.csv(comp_table, "output/sample_composition.csv", row.names = FALSE)

desc_plot_data <- sample %>%
  group_by(year, educ_group) %>%
  summarise(mean_log_wage = weighted.mean(log_wage, perwt), .groups = "drop")

p_desc <- ggplot(desc_plot_data, aes(x = year, y = mean_log_wage, colour = educ_group)) +
  geom_line(linewidth = 1) +
  geom_point() +
  labs(x = "Year", y = "Mean log real hourly wage (2010 dollars)",
       colour = "Education group",
       title = "Real wages by education group, 2010-2024") +
  theme_minimal()
ggsave("output/fig_raw_wages_by_group.png", p_desc, width = 7, height = 4.5)

# --- Distribution statistics (for the paper's Data section) -----------------

weighted_quantile <- function(x, w, probs = 0.5) {
  ord   <- order(x)
  x     <- x[ord]
  w     <- w[ord]
  cum_w <- cumsum(w) / sum(w)
  sapply(probs, function(p) x[which(cum_w >= p)[1]])
}

dist_stats <- sample %>%
  group_by(educ_group) %>%
  summarise(
    n              = n(),
    mean_wage      = weighted.mean(hourly_wage, perwt),
    sd_wage        = sqrt(sum(perwt * (hourly_wage - weighted.mean(hourly_wage, perwt))^2) / sum(perwt)),
    p10_wage       = weighted_quantile(hourly_wage, perwt, 0.10),
    median_wage    = weighted_quantile(hourly_wage, perwt, 0.50),
    p90_wage       = weighted_quantile(hourly_wage, perwt, 0.90),
    mean_log_wage  = weighted.mean(log_wage, perwt),
    sd_log_wage    = sqrt(sum(perwt * (log_wage - weighted.mean(log_wage, perwt))^2) / sum(perwt)),
    .groups = "drop"
  )
print(dist_stats)
write.csv(dist_stats, "output/distribution_statistics_by_group.csv", row.names = FALSE)

# Weighted kernel density of log real hourly wage by group (pooled across
# all years) -- shows the shape and overlap of the two distributions, which
# a mean/median table alone cannot convey (e.g. right-skew, spread, overlap).
p_density <- ggplot(sample, aes(x = log_wage, weight = perwt, colour = educ_group,
                                fill = educ_group)) +
  geom_density(alpha = 0.25, linewidth = 1) +
  labs(x = "Log real hourly wage (2010 dollars)", y = "Density",
       colour = "Education group", fill = "Education group",
       title = "Distribution of real hourly wages by education group, pooled 2010-2024") +
  theme_minimal()
ggsave("output/fig_wage_distribution_density.png", p_density, width = 7, height = 4.5)

## 6. Pooled cross-section: year-by-year regressions -------------------------------

years <- sort(unique(sample$year))
yearly_results <- lapply(years, function(yr) {
  fit <- lm(log_wage ~ university + age + I(age^2) + female,
            data = filter(sample, year == yr),
            weights = perwt)
  tidy(fit) %>%
    filter(term == "university") %>%
    mutate(year = yr)
}) %>% bind_rows()

print(yearly_results)
write.csv(yearly_results, "output/yearly_gap_coefficients.csv", row.names = FALSE)

p_gap <- ggplot(yearly_results, aes(x = year, y = estimate)) +
  geom_line() +
  geom_point() +
  geom_ribbon(aes(ymin = estimate - 1.96 * std.error,
                  ymax = estimate + 1.96 * std.error), alpha = 0.15) +
  labs(x = "Year", y = expression(beta[1] ~ "(conditional wage gap)"),
       title = "Conditional university wage gap over time (year-by-year OLS)") +
  theme_minimal()
ggsave("output/fig_yearly_gap.png", p_gap, width = 7, height = 4.5)

## 7. Pooled regression with year interactions (2010 = reference year) -------------

sample <- sample %>% mutate(year_f = relevel(factor(year), ref = "2010"))

pooled_interact <- feols(
  log_wage ~ university * year_f + age + I(age^2) + female,
  data = sample,
  weights = ~perwt,
  cluster = ~serial
)
summary(pooled_interact)

wald(pooled_interact, keep = "university:year_f")

## 8. Export regression tables -------------------------------------------------------

tidy(pooled_interact) %>%
  mutate(model = "Pooled + Year Interactions") %>%
  write.csv("output/regression_tables.csv", row.names = FALSE)

tryCatch({
  modelsummary(
    list("Pooled + Year Interactions" = pooled_interact),
    output = "output/regression_tables.docx"
  )
}, error = function(e) message("modelsummary export skipped: ", conditionMessage(e)))

## 9. ROBUSTNESS EXTENSION (speculative): debt-adjusted wage gap ------------------
# ==========================================================================
#
# ASSUMPTIONS:
# 1. Debt figures are national averages, not person-specific -- everyone
# in a group is assigned the same debt burden regardless of the school
# they attended, whether they received aid, or whether they've already
# paid the loan off.
# 2. The annual "debt burden" uses the TOTAL amount repaid over a standard
# loan life (principal + interest via amortization), not just principal
# divided evenly -- since loans are very rarely repaid interest-free.
# 3. Within the vocational group, the debt burden is applied only to actual
# Associate's-degree holders (EDUCD == 81). Workers classified as
# vocational solely via industry (construction, IND == 770) are assigned
# $0 debt, since many enter the trades via paid apprenticeship rather
# than a debt-financed credential -- applying the Associate's-level
# figure to that whole subgroup would overstate their debt burden.
# 4. The same annual payment is applied to every person aged 25-64 in a
# group, regardless of how long ago they graduated -- this overstates
# the burden for older workers who have likely finished repayment.
# 5. Debt figures are in current (~2024) nominal dollars, not converted to
# the 2010-dollar basis used for INCWAGE_CPIU_2010 elsewhere in this
# script -- a further simplification, consistent with this section's
# explicitly speculative, order-of-magnitude purpose.
#
# SOURCES:
# - Avg. federal student loan debt by educational attainment: Bachelor's
# degree holders, $29,550; Associate's degree holders, $20,340.
# Hanson, M. (2026). "Student Loan Debt Statistics." Education Data
# Initiative. https://educationdata.org/student-loan-debt-statistics
# (updated July 16, 2026).
# - Federal undergraduate Direct Loan interest rate (6.52%) and standard
# 10-year repayment term: Federal Student Aid, U.S. Department of
# Education. Electronic Announcement GENERAL-26-33, "Interest Rates for
# Federal Direct Loans First Disbursed Between July 1, 2026 and June 30,
# 2027" (2026).
# ==========================================================================

# --- Amortized annual payment (principal + interest, standard 10-yr term) --
amortized_annual_payment <- function(principal, annual_rate = 0.0652, years = 10) {
  r <- annual_rate / 12
  n <- years * 12
  monthly_payment <- principal * r / (1 - (1 + r)^(-n))
  monthly_payment * 12
}

debt_principal_bachelors  <- 29550
debt_principal_associates <- 20340

annual_debt_bachelors  <- amortized_annual_payment(debt_principal_bachelors)
annual_debt_associates <- amortized_annual_payment(debt_principal_associates)

cat("Assumed annual debt service -- Bachelor's: $", round(annual_debt_bachelors, 0),
    " | Associate's: $", round(annual_debt_associates, 0), "\n", sep = "")

# --- Apply group-specific debt burden and recompute wages -------------------
sample_debt <- sample %>%
  mutate(
    annual_debt_payment = case_when(
      university == 1                    ~ annual_debt_bachelors,
      vocational == 1 & educd == 81      ~ annual_debt_associates,
      TRUE                                ~ 0   # trades-industry-only: assumed no postsecondary debt
    ),
    incwage_debt_adj     = incwage_cpiu_2010 - annual_debt_payment,
    hourly_wage_debt_adj = if_else(annual_hours > 0,
                                   incwage_debt_adj / annual_hours, NA_real_),
    log_wage_debt_adj    = log(hourly_wage_debt_adj)
  ) %>%
  filter(is.finite(log_wage_debt_adj))

# --- Year-by-year OLS, debt-adjusted wage, mirrors Section 6 ----------------
yearly_results_debt_adj <- lapply(years, function(yr) {
  fit <- lm(log_wage_debt_adj ~ university + age + I(age^2) + female,
            data = filter(sample_debt, year == yr),
            weights = perwt)
  tidy(fit) %>%
    filter(term == "university") %>%
    mutate(year = yr)
}) %>% bind_rows()

write.csv(yearly_results_debt_adj, "output/yearly_gap_coefficients_debt_adjusted.csv",
          row.names = FALSE)

# --- Compare raw vs. debt-adjusted gap on one plot ---------------------------
gap_comparison <- bind_rows(
  yearly_results        %>% mutate(series = "Raw wage gap"),
  yearly_results_debt_adj %>% mutate(series = "Debt-adjusted wage gap (speculative)")
)
write.csv(gap_comparison, "output/gap_comparison_raw_vs_debt_adjusted.csv", row.names = FALSE)

p_debt_compare <- ggplot(gap_comparison, aes(x = year, y = estimate, colour = series)) +
  geom_line(linewidth = 1) +
  geom_point() +
  geom_ribbon(aes(ymin = estimate - 1.96 * std.error,
                  ymax = estimate + 1.96 * std.error, fill = series),
              alpha = 0.12, colour = NA) +
  labs(x = "Year", y = expression(beta[1] ~ "(conditional wage gap)"),
       colour = "", fill = "",
       title = "Raw vs. debt-adjusted university wage gap (speculative robustness check)",
       subtitle = "Debt burden applied at the group level using national average figures -- see script comments for assumptions") +
  theme_minimal() +
  theme(legend.position = "bottom")
ggsave("output/fig_debt_adjusted_gap_comparison.png", p_debt_compare, width = 7.5, height = 5)

cat("\nDebt-adjusted robustness check complete. Compare estimate columns in\n",
    "output/gap_comparison_raw_vs_debt_adjusted.csv and see\n",
    "output/fig_debt_adjusted_gap_comparison.png\n", sep = "")

# ==========================================================================
# End of script
# ==========================================================================