# When Animal Spirits Catch the News: Policy Uncertainty Shocks and US Consumer Confidence

Local projection impulse responses of US consumer sentiment to unexpected shocks in news-based economic policy uncertainty (EPU), monthly data, 1979 to 2025. All code is in R.

Group project (Group 5) for *Economic Data Analysis: Macroeconomics* (*Ökonomische Datenanalyse: Makroökonomik*), Paris Lodron University of Salzburg, Winter Semester 2025/26.

**Group members:** Benjamin Bell, Krystof Folbrecht, Fedir Maksymiuk, Karolin Mayer.

## Summary

Keynes's "animal spirits" idea says households act on confidence and fear when the future is uncertain. Households rarely read primary policy sources, so the media may be the channel through which uncertainty reaches them. I ask: **to what extent does media-reported economic policy uncertainty influence households' confidence in future economic development?**

- I extract the *unexpected* part of monthly changes in the news-based EPU index and treat it as a shock.
- I trace the response of consumer sentiment over 36 months with local projections.
- A one-standard-deviation EPU shock lowers the monthly change in consumer sentiment by about 0.08 percentage points in the following month, which is statistically significant at the 95% level. At almost every other horizon the response is statistically indistinguishable from zero.
- The effect is therefore small, short-lived and fades quickly. These are associations, not causal effects.

## Data

All series are monthly, downloaded from the Federal Reserve Economic Data (FRED) API with the `fredr` package.

| Role | Series | FRED ID |
|---|---|---|
| Outcome | University of Michigan Consumer Sentiment Index (1966 Q1 = 100) | `UMCSENT` |
| Shock source | News-based Economic Policy Uncertainty Index (Baker, Bloom and Davis) | `USEPUNEWSINDXM` |
| Control | Consumer Price Index | `CPIAUCSL` |
| Control | Unemployment rate | `UNRATE` |
| Control | Federal funds rate | `FEDFUNDS` |

The sample starts in February 1979, the first month after the 12 lags needed for the shock regression. The data were downloaded in 2025, so it ends at the latest month available then (september). The script has no end-date filter and always downloads the latest data, so rerunning it later will include newer months and give slightly different results unless you add one (see *Running*). FRED also revises some series over time.

## Method

1. **Stationarity.** Augmented Dickey-Fuller tests run during the project found the index-form (level) series non-stationary and the transformed series stationary. Consumer sentiment, EPU, CPI and the unemployment rate are therefore converted to monthly percentage changes. The script keeps the tests on the transformed series, which reject a unit root; the level-series tests were removed from the final script. The federal funds rate stays in levels.
2. **Identifying EPU shocks.** The monthly percentage change in EPU is regressed on 12 of its own lags and one-month lags of the CPI and unemployment changes and of the federal funds rate. The residual is the unexpected part of EPU. It is standardised to have unit standard deviation (`epu_shock_std`).
3. **Local projections.** Following Jordà (2005) and using the `lpirfs` package (`lp_lin`), I estimate the response of consumer sentiment to the shock at horizons 0 to 36 months. The system contains the standardised shock and the sentiment change, with two lags of each, and the CPI, unemployment and federal funds variables as exogenous controls with two lags. Bands are 95% (1.96 standard errors).
4. **Plot.** The impulse response is shown with a shaded confidence band and a zero line.

## Results

Response of the monthly percentage change in consumer sentiment (percentage points) to a one-standard-deviation EPU shock:

| Horizon (months) | Response | 95% band |
|---|---|---|
| 1 | -0.084 | [-0.165, -0.004] |
| 12 | 0.063 | [-0.008, 0.135] |
| 13 | -0.063 | [-0.135, 0.010] |
| 24 | 0.075 | [0.014, 0.136] |
| All other horizons, 2 to 36 | between -0.056 and 0.058 | all include zero |

- Horizon 0 is reported as exactly zero with no band, so the first informative horizon is 1 month.
- Only horizon 1 shows a significant negative response. With 36 horizons and 95% bands, about two significant results would be expected by chance, so the isolated positive response at horizon 24 should not be over-interpreted.
- The response is a response of the *monthly change* in sentiment. To read it as an effect on the sentiment *level*, the responses would need to be cumulated.

## Limitations

- **Measurement.** The EPU index counts newspaper coverage, so it reflects media attention as well as true policy uncertainty.
- **Shock construction.** The shock depends on the lag structure and controls chosen and may still contain predictable components. The first-stage regression is estimated on the full sample, and the local projections do not account for the fact that the shock is itself estimated.
- **Frequency and survey data.** Monthly data and survey-based confidence measures smooth short-term reactions and contain subjective bias.
- **Specification.** The federal funds rate is used in levels and was not tested for stationarity. Results use one set of lags and one definition of the shock, and no robustness checks are reported.
- **External validity.** US data and one specific media-based index, so results may not generalise to other countries or media environments.

## Folder structure

```
UMCSENT EPU shocks USA 1979-2025/
  README.md
  epu_consumer_confidence.R   # data download, transformations, shock construction, local projections, plot
  figures/                    # impulse response plot
```

### Requirements

R with the packages `fredr`, `lubridate`, `dplyr`, `tidyr`, `lpirfs`, `tseries` and `ggplot2`. A free FRED API key is needed: request one at https://fredaccount.stlouisfed.org/apikeys.

### Running

1. Store your key as an environment variable named `FRED_API_KEY` (for example in `~/.Renviron`) and use `fredr_set_key(Sys.getenv("FRED_API_KEY"))` in the script. Never put the key in the code.
2. To reproduce the sample used in the project, add `filter(date <= ymd("YYYY-MM-01"))` to the merge step, with the last month of the original sample 2025-09-01. FRED dates fall on the first of each month.
3. Run the script from top to bottom. The impulse response table prints to the console, and the plot is saved to `figures/irf_consumer_confidence.png`.

## Authorship and tools

This was a group project. Research Question, Motivation, and Relevance (Karolin Mayer), Coding, Methodlogy, and Analysis (Benjamin Bell), Coding and Datasets (Krystof Folbrecht), Theory, Literature Research, Evaluation and Conclusion (Fedir Maksymiuk)


## References

- Baker, S.R., Bloom, N. and Davis, S.J. (2016). Measuring economic policy uncertainty. *Quarterly Journal of Economics*, 131(4), 1593-1636.
- Jordà, Ò. (2005). Estimation and inference of impulse responses by local projections. *American Economic Review*, 95(1), 161-182.
- Adämmer, P. (2019). lpirfs: An R package to estimate impulse response functions by local projections. *The R Journal*, 11(2), 421-438.
- Dickey, D.A. and Fuller, W.A. (1979). Distribution of the estimators for autoregressive time series with a unit root. *Journal of the American Statistical Association*, 74(366), 427-431.
- Keynes, J.M. (1936). *The General Theory of Employment, Interest and Money.* London: Macmillan.
- Data: Federal Reserve Bank of St. Louis, FRED (`UMCSENT`, `USEPUNEWSINDXM`, `CPIAUCSL`, `UNRATE`, `FEDFUNDS`); University of Michigan, Surveys of Consumers.
