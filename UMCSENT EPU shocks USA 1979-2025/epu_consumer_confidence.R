#------------------------------------------------------------------------------
# 0) Packages (install once, then comment out install.packages lines)
#install.packages(c("fredr", "lubridate", "dplyr", "tidyr", "lpirfs", "tseries", "ggplot2"))

library(fredr)
library(lubridate)
library(dplyr)
library(tidyr)
library(lpirfs)
library(tseries)
library(ggplot2)

#------------------------------------------------------------------------------
# 1) FRED API key
# The key is read from an environment variable so it is never stored in the code.
# Get a free key at https://fredaccount.stlouisfed.org/apikeys and add this line
# to your ~/.Renviron file:  FRED_API_KEY=your_key_here   (then restart R)
fred_key <- Sys.getenv("FRED_API_KEY")
if (fred_key == "") stop("FRED_API_KEY is not set. See the note above.")
fredr_set_key(fred_key)

# Optional: last month of the sample. The project used data downloaded in 2025,
# so set this to the last month available then (FRED dates are first-of-month),
# e.g. end_date <- ymd("2025-11-01"). The default keeps all available data.
end_date <- ymd("2100-12-31")

#------------------------------------------------------------------------------
# 2) Download series (levels)
cc     <- fredr(series_id = "UMCSENT")        # Consumer sentiment (index)
epu    <- fredr(series_id = "USEPUNEWSINDXM") # EPU (index)
cpi    <- fredr(series_id = "CPIAUCSL")       # CPI (index)
unrate <- fredr(series_id = "UNRATE")         # Unemployment rate (level)
ffr    <- fredr(series_id = "FEDFUNDS")       # Fed Funds rate (level)

#------------------------------------------------------------------------------
# 3) Create monthly % change tables for each main variable (pc_*)
pc_cc_table <- cc %>%
  select(date, value) %>%
  arrange(date) %>%
  mutate(pc_cc = 100 * (value - lag(value, 1)) / lag(value, 1)) %>%
  select(date, pc_cc)

pc_epu_table <- epu %>%
  select(date, value) %>%
  arrange(date) %>%
  mutate(pc_epu = 100 * (value - lag(value, 1)) / lag(value, 1)) %>%
  select(date, pc_epu)

pc_cpi_table <- cpi %>%
  select(date, value) %>%
  arrange(date) %>%
  mutate(pc_cpi = 100 * (value - lag(value, 1)) / lag(value, 1)) %>%
  select(date, pc_cpi)

pc_unrate_table <- unrate %>%
  select(date, value) %>%
  arrange(date) %>%
  mutate(pc_unrate = 100 * (value - lag(value, 1)) / lag(value, 1)) %>%
  select(date, pc_unrate)

# Fed funds kept in levels (common macro choice)
ffr_df <- ffr %>%
  select(date, value) %>%
  arrange(date) %>%
  rename(fedfunds = value)

#------------------------------------------------------------------------------
# 4) Merge into one dataset + choose monthly sample start + drop missing
data_clean <- pc_cc_table %>%
  inner_join(pc_epu_table,    by = "date") %>%
  inner_join(pc_cpi_table,    by = "date") %>%
  inner_join(pc_unrate_table, by = "date") %>%
  inner_join(ffr_df,          by = "date") %>%
  arrange(date) %>%
  filter(date >= ymd("1978-01-01"), date <= end_date) %>%
  drop_na()

#------------------------------------------------------------------------------
# 5) (Optional) Unit root tests on the % change series
adf.test(data_clean$pc_cc)
adf.test(data_clean$pc_epu)
adf.test(data_clean$pc_cpi)
adf.test(data_clean$pc_unrate)

# (Optional) The same tests on the original index-form (level) series, which
# were non-stationary and motivated the move to % changes. Uncomment to run:
# adf.test(na.omit(cc$value))
# adf.test(na.omit(epu$value))
# adf.test(na.omit(cpi$value))
# adf.test(na.omit(unrate$value))

#------------------------------------------------------------------------------
#------------------------------------------------------------------------------
# 6) Build news shock: AR(12) on pc_epu with lagged controls

# 6a) Create lags of pc_epu (1..12)
for (i in 1:12) {
  data_clean[[paste0("pc_epu_L", i)]] <- dplyr::lag(data_clean$pc_epu, i)
}

# 6b) Lag controls by 1 month (Fed funds in levels)
data_clean <- data_clean %>%
  mutate(
    pc_cpi_L1    = lag(pc_cpi, 1),
    pc_unrate_L1 = lag(pc_unrate, 1),
    fedfunds_L1  = lag(fedfunds, 1)
  )

# 6c) Keep only rows where all lags exist
data_est <- data_clean %>%
  drop_na(starts_with("pc_epu_L"), pc_cpi_L1, pc_unrate_L1, fedfunds_L1)

# 6d) AR(12) forecasting regression for expected pc_epu
epu_lag_terms <- paste0("pc_epu_L", 1:12, collapse = " + ")
shock_formula <- as.formula(
  paste("pc_epu ~", epu_lag_terms, "+ pc_cpi_L1 + pc_unrate_L1 + fedfunds_L1")
)

epu_ar12 <- lm(shock_formula, data = data_est)

# 6e) Compute shocks (unexpected part of pc_epu) and standardise
data_est <- data_est %>%
  mutate(
    pc_epu_hat    = predict(epu_ar12, newdata = data_est),
    epu_shock     = pc_epu - pc_epu_hat,
    epu_shock_std = epu_shock / sd(epu_shock, na.rm = TRUE)  # Standardised shock
  )

# 6f) Update main dataset with estimation sample
data_clean <- data_est

#------------------------------------------------------------------------------
# 7) Local Projections (lpirfs) - extended horizon
lp_cc_epu <- lp_lin(
  endog_data      = data_clean %>% select(epu_shock_std, pc_cc),
  lags_endog_lin  = 2,
  trend           = 0,
  shock_type      = 0,               # already standardised
  exog_data       = data_clean %>% select(pc_cpi, pc_unrate, fedfunds),
  lags_exog       = 2,
  hor             = 36,              # extended horizon to 36 months
  confint         = 1.96
)

#------------------------------------------------------------------------------
# 8) Extract IRF results
irf_mean <- lp_cc_epu$irf_lin_mean[1, , 2]
irf_low  <- lp_cc_epu$irf_lin_low[1, , 2]
irf_up   <- lp_cc_epu$irf_lin_up[1, , 2]
horizon <- 0:(length(irf_mean) - 1)

irf_df <- data.frame(
  horizon = horizon,
  irf     = irf_mean,
  lower   = irf_low,
  upper   = irf_up
)
irf_df$significant <- ifelse(irf_df$lower > 0 | irf_df$upper < 0, TRUE, FALSE)
print(irf_df)

#------------------------------------------------------------------------------
# 9) Plot IRF with ggplot2 (smoothed line + shaded confidence bands)
ggplot(irf_df, aes(x = horizon, y = irf)) +
  geom_ribbon(aes(ymin = lower, ymax = upper), fill = "lightblue", alpha = 0.3) +  # shaded confidence band
  geom_line(color = "darkred", linewidth = 0.8) +                                 # single thin IRF line
  geom_hline(yintercept = 0, linetype = "dashed", color = "darkgrey") +          # zero line
  labs(
    x = "Months after shock (horizon)",
    y = "Response of Consumer Confidence",
    title = "Impulse Response of Consumer Confidence to 1 SD EPU Shock"
  ) +
  theme_minimal(base_size = 14)

# Save the plot (saves the last plot drawn)
dir.create("figures", showWarnings = FALSE)
ggsave("figures/irf_consumer_confidence.png", width = 8, height = 5, dpi = 300)
