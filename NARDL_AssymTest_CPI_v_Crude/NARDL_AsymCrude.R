# =============================================================================
# NARDL — ASYMMETRIC RESPONSE OF CPI TO OIL PRICE CHANGES
# Countries: US, Germany, UK  |  Period: Jan 2000 – Feb 2026 (monthly)
# =============================================================================
setwd("/Users/benbell/Desktop/$/LPs_M_Ö_D_A")
# Load required packages, installing any that are missing
pkgs <- c("fredr", "dplyr", "lubridate", "dynlm",
          "lmtest", "sandwich", "tseries",
          "ggplot2", "patchwork", "tidyr")

new <- pkgs[!pkgs %in% installed.packages()[, "Package"]]
if (length(new)) install.packages(new, repos = "https://cloud.r-project.org")
invisible(lapply(pkgs, library, character.only = TRUE))
# fredr: FRED API | dynlm: dynamic lag models | lmtest/sandwich: robust tests
# tseries: Jarque-Bera | ggplot2/patchwork: plots

# ---- API & Date Range -------------------------------------------------------

fredr_set_key("3607267b42abc17f5cadb92941a8b90d")
# Set FRED API key 

START <- as.Date("2000-01-01")
END   <- as.Date("2026-02-28")
# Sample covers Jan 2000 to Feb 2026, giving ~313 monthly observations per country

# ---- Data Acquisition -------------------------------------------------------

pull_fred <- function(id, name) {
  fredr(series_id = id,
        observation_start = START,
        observation_end   = END,
        frequency = "m",
        aggregation_method = "avg") %>%
    select(date, value) %>%
    mutate(date = as.Date(format(date, "%Y-%m-01"))) %>%
    rename(!!name := value)
}
# Pulls a monthly FRED series and standardises all dates to the 1st of each month
# ensuring clean joins across series with different date conventions

cpi_us <- pull_fred("CPIAUCSL",        "cpi")
cpi_uk <- pull_fred("GBRCPIALLMINMEI", "cpi")
cpi_de <- pull_fred("DEUCPIALLMINMEI", "cpi")
# Consumer Price Index for each country — all are price level indices (not growth rates)
# so log transformation is valid

bond_us <- pull_fred("GS10",             "bond")
bond_uk <- pull_fred("IRLTLT01GBM156N",  "bond")
bond_de <- pull_fred("IRLTLT01DEM156N",  "bond")
# 10-year government bond yields — controls for long-run inflation expectations

unemp_us <- pull_fred("UNRATE",          "unemp")
unemp_uk <- pull_fred("LRHUTTTTGBM156S", "unemp")
unemp_de <- pull_fred("LRHUTTTTDEM156S", "unemp")
# Monthly unemployment rates — controls for demand-side inflationary pressure

exr_uk <- pull_fred("DEXUSUK", "exr_raw") %>%
  mutate(exr = 1 / exr_raw) %>%
  select(date, exr)

exr_de <- pull_fred("DEXUSEU", "exr_raw") %>%
  mutate(exr = 1 / exr_raw) %>%
  select(date, exr)
# FRED reports USD per GBP/EUR, so we invert to get domestic currency per USD
# Exchange rate included for UK and DE only — Brent is priced in USD so
# currency movements affect the domestic cost of oil imports

brent <- pull_fred("POILBREUSDM", "oil_price")
# Brent crude spot price in USD/barrel — used as the global oil price benchmark

# ---- PACL Decomposition (Shin, Yu & Greenwood-Nimmo, 2014) ------------------

brent <- brent %>%
  arrange(date) %>%
  mutate(
    log_oil = log(oil_price),
    d_log   = c(NA, diff(log_oil)),
    oil_pos = cumsum(replace(pmax(d_log, 0), is.na(d_log), 0)),
    oil_neg = cumsum(replace(pmin(d_log, 0), is.na(d_log), 0))
  )
# The PACL (Partial sum decomposition) splits log oil price changes into two series:
# oil_pos: running total of all positive log changes (price increases only)
# oil_neg: running total of all negative log changes (price decreases only)
# This allows the model to estimate separate responses to rises and falls in oil prices
# rather than assuming they are equal and opposite as a linear model would

# ---- Build Country Datasets -------------------------------------------------

make_data <- function(cpi_df, bond_df, unemp_df, brent_df, exr_df = NULL) {
  df <- cpi_df %>%
    left_join(bond_df,  by = "date") %>%
    left_join(unemp_df, by = "date") %>%
    left_join(brent_df %>% select(date, oil_pos, oil_neg), by = "date")
  
  if (!is.null(exr_df)) df <- left_join(df, exr_df, by = "date")
  
  df <- df %>%
    arrange(date) %>%
    mutate(log_cpi = log(cpi))
  
  if ("exr" %in% names(df)) {
    df <- df %>% mutate(log_exr = log(exr))
  }
  
  df %>% filter(complete.cases(.))
}
# Merges all series for a given country on date
# log_cpi is the dependent variable — working in logs linearises the price level
# log_exr only added for UK and DE since the US model has no exchange rate
# complete.cases() drops any rows where any variable has a missing value

dat_us <- make_data(cpi_us, bond_us, unemp_us, brent)
dat_uk <- make_data(cpi_uk, bond_uk, unemp_uk, brent, exr_uk)
dat_de <- make_data(cpi_de, bond_de, unemp_de, brent, exr_de)

cat(sprintf("Obs — US: %d | UK: %d | DE: %d\n",
            nrow(dat_us), nrow(dat_uk), nrow(dat_de)))

# ---- Lag Selection ----------------------------------------------------------

J_MAX <- 12
P_MAX <- 4

aic_grid <- function(df, has_exr = FALSE) {
  start_yr <- year(min(df$date))
  start_mo <- month(min(df$date))
  df_num   <- df %>% select(-date)
  ts_obj   <- ts(df_num, start = c(start_yr, start_mo), frequency = 12)
  # date column dropped before ts() — ts() requires purely numeric input
  
  best <- list(aic = Inf, p = 1, j = 0)
  
  for (p in 1:P_MAX) {
    for (j in 0:J_MAX) {
      tryCatch({
        cpi_terms <- paste(paste0("L(log_cpi,", 1:p, ")"), collapse = "+")
        pos_terms <- paste(paste0("L(oil_pos,", 0:j, ")"), collapse = "+")
        neg_terms <- paste(paste0("L(oil_neg,", 0:j, ")"), collapse = "+")
        ctrl      <- "bond + unemp"
        
        fml <- if (has_exr) {
          exr_terms <- paste(paste0("L(log_exr,", 0:j, ")"), collapse = "+")
          as.formula(paste("log_cpi ~", cpi_terms, "+", pos_terms, "+",
                           neg_terms, "+", exr_terms, "+", ctrl))
        } else {
          as.formula(paste("log_cpi ~", cpi_terms, "+", pos_terms, "+",
                           neg_terms, "+", ctrl))
        }
        
        fit <- dynlm(fml, data = ts_obj)
        a   <- AIC(fit)
        if (a < best$aic) best <- list(aic = a, p = p, j = j)
        
      }, error = function(e) NULL)
    }
  }
  best
}
# Searches all combinations of AR lags p (1-4) and oil lags j (0-12)
# Selects the combination that minimises AIC — balancing fit against complexity
# AIC selected very short lags (j=0-2) so j=4 is fixed below for comparability

lags_us <- list(aic = NA, p = 2, j = 4)
lags_uk <- list(aic = NA, p = 1, j = 4)
lags_de <- list(aic = NA, p = 1, j = 4)
# AR lag p retained from AIC selection, oil lags fixed at j=4 across all countries
# Fixing j=4 ensures plots are comparable and captures up to one quarter of dynamics
# Results were confirmed to be robust — Wald conclusions unchanged at AIC-selected lags

# ---- Estimate NARDL Models --------------------------------------------------

fit_nardl <- function(df, p, j, has_exr = FALSE) {
  start_yr <- year(min(df$date))
  start_mo <- month(min(df$date))
  df_num   <- df %>% select(-date)
  ts_obj   <- ts(df_num, start = c(start_yr, start_mo), frequency = 12)
  
  cpi_terms <- paste(paste0("L(log_cpi,", 1:p, ")"), collapse = "+")
  pos_terms <- paste(paste0("L(oil_pos,", 0:j, ")"), collapse = "+")
  neg_terms <- paste(paste0("L(oil_neg,", 0:j, ")"), collapse = "+")
  ctrl      <- "bond + unemp"
  
  fml <- if (has_exr) {
    exr_terms <- paste(paste0("L(log_exr,", 0:j, ")"), collapse = "+")
    as.formula(paste("log_cpi ~", cpi_terms, "+", pos_terms, "+",
                     neg_terms, "+", exr_terms, "+", ctrl))
  } else {
    as.formula(paste("log_cpi ~", cpi_terms, "+", pos_terms, "+",
                     neg_terms, "+", ctrl))
  }
  
  dynlm(fml, data = ts_obj)
}
# Estimates the NARDL model for a given country using dynlm
# L(x, k) notation includes the variable x at lag k months
# Separate lag sequences for oil_pos and oil_neg allow asymmetric coefficient estimation
# Controls: bond yield and unemployment capture monetary and demand-side conditions

mod_us <- fit_nardl(dat_us, lags_us$p, lags_us$j, FALSE)
mod_uk <- fit_nardl(dat_uk, lags_uk$p, lags_uk$j, TRUE)
mod_de <- fit_nardl(dat_de, lags_de$p, lags_de$j, TRUE)

vcov_us <- vcovHAC(mod_us)
vcov_uk <- vcovHAC(mod_uk)
vcov_de <- vcovHAC(mod_de)
# HAC (Newey-West) robust variance-covariance matrices
# Corrects standard errors for serial correlation and heteroskedasticity
# which are common in monthly macroeconomic time series

# ---- Coefficient Tables -----------------------------------------------------

print_robust <- function(mod, vcov_mat, label) {
  cat("\n", strrep("=", 60), "\n")
  cat(" NARDL Results:", label, "\n")
  cat(strrep("=", 60), "\n")
  print(coeftest(mod, vcov. = vcov_mat))
  cat(sprintf("\n  Adj. R²: %.4f  |  AIC: %.2f  |  N: %d\n",
              summary(mod)$adj.r.squared, AIC(mod), nobs(mod)))
}
# Prints HAC-robust t-tests for each coefficient
# High adj. R² reflects the trending nature of log CPI levels, not just oil

print_robust(mod_us, vcov_us, "United States")
print_robust(mod_uk, vcov_uk, "United Kingdom")
print_robust(mod_de, vcov_de, "Germany")

# ---- Wald Test for Asymmetry ------------------------------------------------

wald_asym <- function(mod, vcov_mat, country) {
  cn      <- names(coef(mod))
  pos_idx <- grep("oil_pos", cn)
  neg_idx <- grep("oil_neg", cn)
  
  beta  <- coef(mod)
  lrm_p <- sum(beta[pos_idx])
  lrm_n <- sum(beta[neg_idx])
  
  R          <- matrix(0, 1, length(beta))
  R[pos_idx] <-  1
  R[neg_idx] <- -1
  
  Rb  <- as.numeric(R %*% beta)
  RVR <- as.numeric(R %*% vcov_mat %*% t(R))
  W   <- Rb^2 / RVR
  pv  <- pchisq(W, df = 1, lower.tail = FALSE)
  
  sig <- case_when(
    pv < 0.01 ~ "***",
    pv < 0.05 ~ "**",
    pv < 0.10 ~ "*",
    TRUE      ~ "n.s."
  )
  
  cat(sprintf(
    "\n[%s] Wald Asymmetry Test\n  LRM+ = %.6f  |  LRM- = %.6f  |  Diff = %.6f\n  W = %.4f  |  p = %.5f  %s\n",
    country, lrm_p, lrm_n, lrm_p - lrm_n, W, pv, sig
  ))
  
  list(country = country, lrm_pos = lrm_p, lrm_neg = lrm_n,
       diff = lrm_p - lrm_n, W = W, pval = pv, sig = sig)
}
# Tests H0: sum of oil+ coefficients = sum of oil- coefficients
# Rejection means the total association between oil price increases and CPI
# differs significantly from that of oil price decreases — i.e. asymmetry
# W statistic is chi-squared distributed with 1 degree of freedom
# Uses the HAC variance matrix so the test is robust to serial correlation

cat("\n", strrep("=", 60), "\n")
cat(" WALD TESTS FOR ASYMMETRY\n")
cat(strrep("=", 60), "\n")
w_us <- wald_asym(mod_us, vcov_us, "US")
w_uk <- wald_asym(mod_uk, vcov_uk, "UK")
w_de <- wald_asym(mod_de, vcov_de, "DE")

# ---- Diagnostic Tests -------------------------------------------------------

run_diag <- function(mod, country) {
  cat(sprintf("\n[%s] Diagnostics\n", country))
  
  bg  <- bgtest(mod, order = 12)
  cat(sprintf("  Breusch-Godfrey (serial corr):    chi2=%.3f, p=%.4f\n",
              bg$statistic, bg$p.value))
  
  bp  <- bptest(mod)
  cat(sprintf("  Breusch-Pagan  (heterosked.):     chi2=%.3f, p=%.4f\n",
              bp$statistic, bp$p.value))
  
  rst <- resettest(mod, power = 2:3, type = "fitted")
  cat(sprintf("  RESET          (functional form): F=%.3f,   p=%.4f\n",
              rst$statistic, rst$p.value))
  
  jb  <- jarque.bera.test(residuals(mod))
  cat(sprintf("  Jarque-Bera    (normality):       chi2=%.3f, p=%.4f\n",
              jb$statistic, jb$p.value))
  
  list(country  = country,
       bg_stat  = round(bg$statistic,  3), bg_p  = round(bg$p.value,  4),
       bp_stat  = round(bp$statistic,  3), bp_p  = round(bp$p.value,  4),
       rst_stat = round(rst$statistic, 3), rst_p = round(rst$p.value, 4),
       jb_stat  = round(jb$statistic,  3), jb_p  = round(jb$p.value,  4))
}
# Breusch-Godfrey: tests for serial correlation up to 12 lags
# Breusch-Pagan:   tests for heteroskedasticity in residuals
# RESET:           tests whether nonlinear terms improve fit (functional form)
# Jarque-Bera:     tests whether residuals follow a normal distribution
# Failures are expected in monthly macro data — HAC standard errors
# correct inference for serial correlation and heteroskedasticity throughout

cat("\n", strrep("=", 60), "\n")
cat(" DIAGNOSTIC TESTS\n")
cat(strrep("=", 60), "\n")
diag_us <- run_diag(mod_us, "US")
diag_uk <- run_diag(mod_uk, "UK")
diag_de <- run_diag(mod_de, "DE")

# ---- Coefficient Plots ------------------------------------------------------

extract_coefs <- function(mod, vcov_mat, country) {
  cn  <- names(coef(mod))
  b   <- coef(mod)
  se  <- sqrt(diag(vcov_mat))
  
  pos_idx <- grep("oil_pos", cn)
  neg_idx <- grep("oil_neg", cn)
  
  bind_rows(
    data.frame(lag = seq_along(pos_idx) - 1, coef = b[pos_idx],
               se = se[pos_idx], type = "Oil+ (price increase)", country = country),
    data.frame(lag = seq_along(neg_idx) - 1, coef = b[neg_idx],
               se = se[neg_idx], type = "Oil- (price decrease)", country = country)
  ) %>%
    mutate(lo = coef - 1.96 * se, hi = coef + 1.96 * se)
}
# Extracts oil+ and oil- coefficients with HAC standard errors for plotting
# Confidence bands computed as ±1.96 SE giving approximate 95% intervals

coefs <- bind_rows(
  extract_coefs(mod_us, vcov_us, "United States"),
  extract_coefs(mod_uk, vcov_uk, "United Kingdom"),
  extract_coefs(mod_de, vcov_de, "Germany")
) %>%
  mutate(country = factor(country, c("United States", "United Kingdom", "Germany")))

p_coef <- ggplot(coefs, aes(lag, coef, color = type, fill = type)) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "grey60", linewidth = .5) +
  geom_ribbon(aes(ymin = lo, ymax = hi), alpha = .15, color = NA) +
  geom_line(linewidth = .9) +
  geom_point(size = 2.2) +
  facet_wrap(~country, ncol = 1, scales = "free_y") +
  scale_color_manual(values = c("Oil+ (price increase)" = "#c0392b",
                                "Oil- (price decrease)" = "#2980b9")) +
  scale_fill_manual(values  = c("Oil+ (price increase)" = "#c0392b",
                                "Oil- (price decrease)" = "#2980b9")) +
  scale_x_continuous(breaks = 0:J_MAX) +
  labs(title    = "NARDL Lag Coefficients — Oil Partial Sums on log(CPI)",
       subtitle = "95% CI (HAC Newey-West). Asymmetry = divergence between red and blue.",
       x = "Lag (months)", y = "Coefficient", color = NULL, fill = NULL) +
  theme_bw(base_size = 11) +
  theme(legend.position  = "top",
        strip.background = element_rect(fill = "#1a2a3a"),
        strip.text       = element_text(color = "white", face = "bold"))
# Each point shows the association between that lagged oil partial sum and current log CPI
# Divergence between red (oil+) and blue (oil-) at lag 0 is the primary visual signal
# free_y scales each panel independently — band width differences across countries
# are partly a visual artefact of differing y-axis ranges, not just precision

p_cum <- coefs %>%
  group_by(country, type) %>%
  arrange(lag) %>%
  mutate(cum    = cumsum(coef),
         cum_lo = cumsum(lo),
         cum_hi = cumsum(hi)) %>%
  ungroup() %>%
  ggplot(aes(lag, cum, color = type, fill = type)) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "grey60", linewidth = .5) +
  geom_ribbon(aes(ymin = cum_lo, ymax = cum_hi), alpha = .12, color = NA) +
  geom_line(linewidth = .9) +
  geom_point(size = 2) +
  facet_wrap(~country, ncol = 1, scales = "free_y") +
  scale_color_manual(values = c("Oil+ (price increase)" = "#c0392b",
                                "Oil- (price decrease)" = "#2980b9")) +
  scale_fill_manual(values  = c("Oil+ (price increase)" = "#c0392b",
                                "Oil- (price decrease)" = "#2980b9")) +
  scale_x_continuous(breaks = 0:J_MAX) +
  labs(title    = "Cumulative Long-Run Multipliers",
       subtitle = "Converging lines = symmetric. Diverging = asymmetric pass-through.",
       x = "Horizon (months)", y = "Cumulative effect on log(CPI)",
       color = NULL, fill = NULL) +
  theme_bw(base_size = 11) +
  theme(legend.position  = "top",
        strip.background = element_rect(fill = "#1a2a3a"),
        strip.text       = element_text(color = "white", face = "bold"))
# Running sum of coefficients across lags — shows total accumulated association
# at each horizon. The gap between lines at the final lag is what the Wald test
# formally tests. Persistent separation indicates asymmetric total association.

combined <- p_coef / p_cum +
  plot_annotation(
    title    = "Asymmetric Inflation Response to Oil Price Changes",
    subtitle = "NARDL model | Jan 2000 – Feb 2026 | HAC-robust standard errors",
    theme    = theme(plot.title    = element_text(face = "bold", size = 13),
                     plot.subtitle = element_text(size = 10, color = "grey40"))
  )

ggsave("nardl_coefficient_plots.png", combined, width = 11, height = 16, dpi = 150)

# ---- AIC Profile Plot -------------------------------------------------------

aic_profile <- function(df, p_fixed, has_exr = FALSE, country = "") {
  start_yr <- year(min(df$date))
  start_mo <- month(min(df$date))
  df_num   <- df %>% select(-date)
  ts_obj   <- ts(df_num, start = c(start_yr, start_mo), frequency = 12)
  
  results <- data.frame(j = 0:J_MAX, aic = NA_real_)
  
  for (j in 0:J_MAX) {
    tryCatch({
      cpi_terms <- paste(paste0("L(log_cpi,", 1:p_fixed, ")"), collapse = "+")
      pos_terms <- paste(paste0("L(oil_pos,", 0:j, ")"), collapse = "+")
      neg_terms <- paste(paste0("L(oil_neg,", 0:j, ")"), collapse = "+")
      ctrl      <- "bond + unemp"
      
      fml <- if (has_exr) {
        exr_terms <- paste(paste0("L(log_exr,", 0:j, ")"), collapse = "+")
        as.formula(paste("log_cpi ~", cpi_terms, "+", pos_terms, "+",
                         neg_terms, "+", exr_terms, "+", ctrl))
      } else {
        as.formula(paste("log_cpi ~", cpi_terms, "+", pos_terms, "+",
                         neg_terms, "+", ctrl))
      }
      
      results$aic[j + 1] <- AIC(dynlm(fml, data = ts_obj))
    }, error = function(e) NULL)
  }
  
  results$country <- country
  results
}
# Re-runs models across j=0 to 12 with p fixed at the AIC-selected value
# Used purely for visualising how AIC varies with lag length — not for estimation

aic_df <- bind_rows(
  aic_profile(dat_us, lags_us$p, FALSE, "United States"),
  aic_profile(dat_uk, lags_uk$p, TRUE,  "United Kingdom"),
  aic_profile(dat_de, lags_de$p, TRUE,  "Germany")
) %>%
  mutate(country = factor(country, c("United States", "United Kingdom", "Germany"))) %>%
  group_by(country) %>%
  mutate(best = aic == min(aic, na.rm = TRUE)) %>%
  ungroup()

p_aic <- ggplot(aic_df, aes(j, aic)) +
  geom_line(color = "#2c3e50", linewidth = .9) +
  geom_point(aes(color = best), size = 3, show.legend = FALSE) +
  scale_color_manual(values = c("FALSE" = "#95a5a6", "TRUE" = "#e74c3c")) +
  facet_wrap(~country, ncol = 1, scales = "free_y") +
  scale_x_continuous(breaks = 0:J_MAX) +
  labs(title    = "AIC Profile — Oil Lag Length Selection",
       subtitle = "Red dot = AIC-optimal j. Fixed j=4 used in estimation for comparability.",
       x = "Oil lag length (j)", y = "AIC") +
  theme_bw(base_size = 11) +
  theme(strip.background = element_rect(fill = "#1a2a3a"),
        strip.text       = element_text(color = "white", face = "bold"))
# Red dot marks the AIC minimum — US at j=2, UK at j=0, DE at j=1
# The monotonically increasing AIC for UK and DE beyond j=0 shows AIC penalising
# extra lags heavily, motivating the fixed j=4 choice for the main results

ggsave("nardl_aic_profile.png", p_aic, width = 9, height = 10, dpi = 150)

# ---- Export Results ---------------------------------------------------------

wald_table <- bind_rows(lapply(list(w_us, w_uk, w_de), as.data.frame))
diag_table <- bind_rows(lapply(list(diag_us, diag_uk, diag_de), as.data.frame))
lag_table  <- data.frame(
  country    = c("US", "UK", "DE"),
  AR_lags_p  = c(lags_us$p, lags_uk$p, lags_de$p),
  oil_lags_j = c(lags_us$j, lags_uk$j, lags_de$j),
  AIC        = round(c(lags_us$aic, lags_uk$aic, lags_de$aic), 2)
)

write.csv(wald_table, "wald_asymmetry_results.csv",  row.names = FALSE)
write.csv(diag_table, "diagnostic_test_results.csv", row.names = FALSE)
write.csv(lag_table,  "selected_lags.csv",           row.names = FALSE)
write.csv(coefs,      "lag_coefficients.csv",         row.names = FALSE)
# Exports all key results to CSV for reference and reporting

cat("\n", strrep("=", 60), "\n")
cat(" FINAL SUMMARY\n")
cat(strrep("=", 60), "\n\n")
cat("Selected lags:\n");  print(lag_table)
cat("\nWald test results:\n"); print(wald_table)
cat("\n*** = 1%  ** = 5%  * = 10%  n.s. = not significant\n")

