# Asymmetric Oil Price Pass-Through to Inflation: Evidence from the US, Germany and the UK

A nonlinear ARDL (NARDL) analysis of whether consumer prices respond differently to rises and falls in the Brent crude oil price, estimated separately for the United States, Germany and the United Kingdom on monthly data from January 2000 to February 2026. All code is in R.

Group project (Group 3) for *Applied Macroeconomics* (*Angewandte Makroökonomik*), Paris Lodron University of Salzburg, Summer Semester 2026.

**Group members:** Benjamin Bell, Fedir Maksymiuk, Karolin Mayer, Silvan Schubert.

## Summary

Prices are often said to rise like rockets and fall like feathers: they climb quickly when costs rise and drift down slowly when costs fall. If oil price pass-through to inflation works that way, models that assume a symmetric response will understate inflation risk when oil prices rise. We ask: **does inflation respond asymmetrically to rising versus falling oil prices, and does this differ across the US, Germany and the UK?**

- **UK and Germany:** the data reject symmetry. Wald tests find that the cumulative association between oil price increases and consumer prices differs significantly from that of oil price decreases.
- **US:** there is not enough evidence to reject symmetry.
- **Robustness:** the conclusions are the same under AIC-selected lag lengths and under a fixed four-lag specification.
- **Germany** shows the largest and most precisely estimated coefficients.
- These are associations, not causal effects.

## Data

All series are monthly and downloaded from the Federal Reserve Economic Data (FRED) API using the `fredr` package. The sample runs from January 2000 to February 2026, about 313 monthly observations per country.

| Variable | US | UK | Germany |
|---|---|---|---|
| Consumer price index (CPI) | `CPIAUCSL` | `GBRCPIALLMINMEI` | `DEUCPIALLMINMEI` |
| 10-year government bond yield | `GS10` | `IRLTLT01GBM156N` | `IRLTLT01DEM156N` |
| Unemployment rate | `UNRATE` | `LRHUTTTTGBM156S` | `LRHUTTTTDEM156S` |
| Exchange rate (domestic currency per USD) | not used | `DEXUSUK` | `DEXUSEU` |
| Brent crude oil price (USD per barrel) | `POILBREUSDM` for all three countries | | |

FRED reports the exchange rates as USD per pound or euro, so the script inverts them. Dates are standardised to the first of each month before the series are merged, and only months with complete data are kept. The data are not included in this repository, and the script downloads them directly.

## Method

1. **Splitting oil price changes.** Following Shin, Yu and Greenwood-Nimmo (2014), the change in the log Brent price is split into positive and negative parts, and each is cumulated into a partial-sum series (`oil_pos` and `oil_neg`). This lets rises and falls have separate coefficients.
2. **Model.** For each country, log CPI is regressed on its own lags, the current and lagged oil partial sums, and controls for the bond yield and the unemployment rate, plus the exchange rate for the UK and Germany. The US model has no exchange rate, because the exchange rate matters for the cost of imported oil in the other two.
3. **Lag lengths.** AIC is used to select the number of autoregressive lags (`p` from 1 to 4) and oil lags (`j` from 0 to 12). AIC picks very short oil lags (US 2, UK 0, Germany 1), so the main models fix `j = 4` for comparability across countries, with `p` of 2 for the US and 1 for the UK and Germany. Results under both choices are compared.
4. **Inference.** Standard errors are heteroskedasticity- and autocorrelation-consistent (Newey-West, `vcovHAC`).
5. **Asymmetry test.** A Wald test of whether the sum of the coefficients on `oil_pos` equals the sum of the coefficients on `oil_neg`, with a chi-squared distribution on one degree of freedom.
6. **Diagnostics.** Breusch-Godfrey (serial correlation), Breusch-Pagan (heteroskedasticity), RESET (functional form) and Jarque-Bera (normality) tests are reported for each model.

## Results

Wald test for asymmetry (H0: symmetric pass-through):

| Country | Specification | W | p-value | Conclusion |
|---|---|---|---|---|
| US | AIC lags | 0.41 | 0.521 | No asymmetry |
| UK | AIC lags | 20.78 | 0.000005 | Asymmetry |
| Germany | AIC lags | 9.44 | 0.002 | Asymmetry |
| US | Fixed 4 oil lags | 0.09 | 0.766 | No asymmetry |
| UK | Fixed 4 oil lags | 19.87 | 0.000008 | Asymmetry |
| Germany | Fixed 4 oil lags | 6.14 | 0.013 | Asymmetry |

- **Significance:** The lag-0 coefficient is often significant, but longer lags mostly are not. Countries whose positive and negative coefficients differ at lag 0 are the ones that fail the Wald test.
- **Magnitude and precision:** Germany has the largest and most precise coefficients, which suggests a stronger association between oil price changes and CPI.
- **Cross-country pattern:** In the US plots the positive and negative lines are tight and overlap far more, with strikingly similar values at lag 0. The UK is similar to Germany but less pronounced.
- **Timing:** The lag coefficient plots suggest the timing of the response differs across countries.

## Limitations

- **Association, not causation.** The analysis does not identify oil price shocks, so policy implications are limited. A natural extension is to use long-run multipliers and identified oil shock mechanisms.
- **No structural break controls** for the 2008, 2020 and 2022 periods, which may affect inflation persistence.
- **Very high R-squared** (above 0.90 in every model). This largely reflects the trending, unit-root-like behaviour of log CPI levels, and may also reflect overfitting.
- **No unit root or cointegration tests** are included in the script, so the long-run interpretation of the NARDL coefficients is not formally tested.
- **Lag selection.** AIC penalises extra oil lags heavily, which made it hard to visualise the dynamics. Adding lags did not materially change the conclusions.
- **Scale of the plots.** Each coefficient panel uses its own y-axis, so differences in band width across countries partly reflect scaling and not only precision.

## Repository structure

```
oil-price-asymmetry-nardl/
  README.md
  Applied_Macro_Final_Code_group_3_.R   # data download, partial sums, NARDL models, Wald tests, diagnostics, plots
  Presentation.pptx                     # slides [add if the group agrees]
  output/                               # figures and CSV results written by the script
```

The script writes these files: `nardl_coefficient_plots.png`, `nardl_aic_profile.png`, `wald_asymmetry_results.csv`, `diagnostic_test_results.csv`, `selected_lags.csv` and `lag_coefficients.csv`.

### Requirements

R with the packages `fredr`, `dplyr`, `lubridate`, `dynlm`, `lmtest`, `sandwich`, `tseries`, `ggplot2`, `patchwork` and `tidyr`. The script installs any that are missing. A free FRED API key is also needed: request one at https://fredaccount.stlouisfed.org/apikeys.

### Running

1. Store your key as an environment variable named `FRED_API_KEY` (for example in `~/.Renviron`) and use `fredr_set_key(Sys.getenv("FRED_API_KEY"))` in the script. Do not put the key in the code.
2. Remove or edit the `setwd()` line near the top, which points to a folder on one team member's computer.
3. Run the script from top to bottom. The main models use the fixed four-lag specification.
4. To reproduce the AIC-lag results, set the lags to the values AIC selected (US: p = 2, j = 2; UK: p = 1, j = 0; Germany: p = 1, j = 1) and rerun the estimation and Wald steps.

## Authorship and tools

This was a group project. [State which parts you wrote and which parts the group wrote together.]

**AI assistance:** [State exactly where AI tools helped, for example "Claude (Anthropic) assisted with ... ". Delete this line if no AI tools were used.]

## References

- Choi, S., Furceri, D., Loungani, P., Mishra, S. and Poplawski-Ribeiro, M. (2018). Oil prices and inflation dynamics: evidence from advanced and developing economies. *Journal of International Money and Finance*, 82, 71-96. https://doi.org/10.1016/j.jimonfin.2017.12.004
- Hamilton, J.D. (1983). Oil and the macroeconomy since World War II. *Journal of Political Economy*, 91(2), 228-248.
- Kilian, L. and Zhou, X. (2023). Oil price shocks and inflation. Federal Reserve Bank of Dallas Working Paper.
- Mork, K.A. (1989). Oil and the macroeconomy when prices go up and down: an extension of Hamilton's results. *Journal of Political Economy*, 97(3), 740-744.
- Shin, Y., Yu, B. and Greenwood-Nimmo, M. (2014). Modelling asymmetric cointegration and dynamic multipliers in a nonlinear ARDL framework. In Sickles, R.C. and Horrace, W.C. (eds), *Festschrift in Honor of Peter Schmidt*. New York: Springer, 281-314.
- Data: Federal Reserve Bank of St. Louis, FRED (series listed above).
