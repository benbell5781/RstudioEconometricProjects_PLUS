# The University Wage Premium vs Vocational Pay in the United States, 2010 to 2024

How has the conditional wage gap between university-educated and vocationally trained workers in the United States changed over time? Pooled cross-sectional analysis of American Community Survey (ACS) microdata. All code is in R.

Term paper for *Models for Panel Data, Binary and Categorical Outcomes* (Master's level), Paris Lodron University of Salzburg, Summer Semester 2026.

## Summary

Tuition, living costs and student debt have risen steadily, which raises the question of whether a four-year degree still pays relative to shorter vocational routes. I estimate the conditional hourly wage gap between the two groups for each year from 2010 to 2024 and test whether it has moved.

- The gap was **0.40 log points (a 49% wage advantage for university workers) in 2010**, rose to **0.48 log points (62%) in 2022**, and eased to **0.46 log points (59%) by 2024**.
- A pooled model with year interactions confirms the change: the year-interaction terms are jointly significant (F = 9.2, p < 2.2e-16), and the gap had grown by up to about 8 log points relative to 2010.
- A speculative **debt-adjusted** robustness check lowers the gap by about 0.05 log points in every year (roughly 10 to 13% of the raw gap) but leaves the pattern unchanged.
- The results are conditional associations, not causal returns to either pathway.

## Data

I use the American Community Survey from **IPUMS USA** (Ruggles et al., 2024), 2010 to 2024. The ACS draws a fresh sample each year and does not follow the same people, so this is a **pooled cross-section** and not a panel. That is why panel methods are not used.

**The data is not included in this repository.** IPUMS terms of use do not allow redistribution of microdata, so no extract, person-level file or sample rows is committed here. To reproduce the analysis:

1. Register for free at https://usa.ipums.org and create your own ACS extract for 2010 to 2024.
2. Select these variables: `YEAR`, `SERIAL`, `PERWT`, `SEX`, `AGE`, `EDUCD`, `EMPSTAT`, `IND`, `WKSWORK2`, `UHRSWORK`, `INCWAGE` and the CPI-adjusted wage `INCWAGE_CPIU_2010`.
3. Save the extract as a CSV with lowercase column names at `data/acs_2010_2024_slim.csv`, which is the path the script reads.
4. Cite IPUMS USA in any work you produce from it (see References).

Sample restrictions: employed people aged 25 to 64 with valid wage data (918,563 observations in my extract).

### Education groups

| Group | Definition |
|---|---|
| University | Bachelor's degree or higher |
| Vocational | Associate's degree, or working in the construction industry without a four-year degree |

Credential takes priority over industry, so a construction worker with a bachelor's degree counts as university. People in neither group are dropped. The vocational group is a rough proxy: the ACS has no data on trade certifications, and the construction industry code covers everyone from labourers to site managers.

### Outcome

Hourly wage in 2010 dollars: inflation-adjusted annual wage income divided by estimated annual hours (usual weekly hours times weeks worked). Weeks worked is reported in brackets, so I use bracket midpoints, which is an approximation. All models use ACS person weights.

## Method

Baseline specification:

```
log(wage) = b0 + b1 * university + b2 * age + b3 * age^2 + b4 * female + e
```

`b1` is the conditional wage gap between university and vocational workers, holding age and sex fixed. The exact percentage difference is `exp(b1) - 1`.

1. **Year-by-year regressions.** The baseline is estimated separately for each year, giving a sequence of `b1` estimates with no assumed shape.
2. **Pooled regression with year interactions.** One model interacts the university indicator with year dummies (2010 is the reference year), so each interaction term is the cumulative change in the gap since 2010. Standard errors are clustered by household, and a joint Wald test checks whether the interaction terms are collectively zero.
3. **Debt-adjusted robustness check.** The year-by-year model is re-estimated after subtracting an estimated annual student-debt payment from the wages of bachelor's and associate's degree holders. I use national average balances of $29,550 (bachelor's) and $20,340 (associate's) (Hanson, 2026), the 6.52% federal undergraduate loan rate (US Department of Education, 2026) and a 10-year amortisation. This is deliberately speculative, since not everyone borrows or repays over 10 years. It is an order-of-magnitude sensitivity check.

Models are estimated with `fixest::feols` and base `lm`.

## Results

Standard errors for the year-by-year estimates are about 0.006 to 0.007 in every year, and all estimates are significant at the 1% level.

| Year | Gap (log points) | Wage premium | Debt-adjusted gap (log points) |
|---|---|---|---|
| 2010 | 0.398 | 48.9% | 0.347 |
| 2011 | 0.406 | 50.1% | 0.357 |
| 2012 | 0.426 | 53.1% | 0.384 |
| 2013 | 0.421 | 52.4% | 0.368 |
| 2014 | 0.442 | 55.6% | 0.383 |
| 2015 | 0.439 | 55.1% | 0.387 |
| 2016 | 0.443 | 55.8% | 0.392 |
| 2017 | 0.463 | 58.9% | 0.414 |
| 2018 | 0.457 | 57.9% | 0.405 |
| 2019 | 0.460 | 58.5% | 0.415 |
| 2020 | 0.452 | 57.2% | 0.399 |
| 2021 | 0.464 | 59.1% | 0.420 |
| 2022 | 0.481 | 61.8% | 0.432 |
| 2023 | 0.481 | 61.7% | 0.432 |
| 2024 | 0.463 | 58.9% | 0.416 |

- **Pooled model:** The 2010 baseline gap is 0.40 (SE 0.0074). Interaction terms are insignificant in 2011 and significant from 2012 onward, peaking at 0.081 (SE 0.0115) in 2022 and standing at 0.066 (SE 0.011) in 2024, still well above 2010.
- **Other coefficients:** Age and age squared enter at 0.076 and -0.00074, and the female coefficient is -0.222, a substantial separate gender wage gap that is not the focus of the paper.
- **Raw wages:** Average hourly wages (2010 dollars) are $36.07 for university workers and $22.10 for vocational workers (medians $26.70 and $17.80). The distributions overlap heavily, and many vocational workers out-earn university workers.
- **Debt adjustment:** The adjustment lowers the gap by a nearly constant 0.047 to 0.052 log points each year, so the debt-adjusted series mirrors the raw one.

## Limitations

- **Correlational, not causal.** Ability bias and selection into schooling mean the gap is not the return either group would receive from switching credentials.
- **Rough vocational proxy.** The construction-industry definition mixes many job types and no trade certifications.
- **Changing composition.** Repeated cross-sections show how each year's workforce differs, not how individuals' earnings changed, so part of the trend may reflect who is in each group.
- **Imputed hours.** The wage measure relies on bracketed weeks worked, and the ACS top-codes high earners, which may understate the top of both distributions.
- **Debt adjustment.** It applies national group averages to everyone and should be read as a sensitivity check only.
- **Possible extensions:** heterogeneity by age, sex, race, region or industry, detailed occupational credentials and individual debt records.

## Folder structure

```
WageGap_Project.R/
  README_WageGap.md
  Wage_Gap_Project.R       # variable construction, regressions, robustness check, exports
  data/                    # not included (see Data)
```

### Requirements

R with the packages `data.table`, `dplyr`, `tidyr`, `ggplot2`, `fixest`, `broom` and `modelsummary`.

### Running

1. Create `data/acs_2010_2024_slim.csv` as described in *Data*.
2. Set the working directory to the repository root and run `Wage_Gap_Project.R` from top to bottom.
3. Tables (CSV, plus a Word table if `modelsummary` exports) and figures are written to `output/`. These are aggregate results only.

## Authorship and tools

I designed the research question and specifications, wrote the regression and analysis code, and interpreted the results.

**AI assistance:** Claude (Anthropic) was used in three ways, as stated in the script header. It helped restructure the original IPUMS extract into the slimmer CSV used here, helped with variable construction so that I did not misclassify coded variables, and helped write the debt-adjustment section (section 9) because I was unfamiliar with the relevant R tools.

## References

- Autor, D., Goldin, C. and Katz, L.F. (2020). *Extending the Race between Education and Technology.* NBER Working Paper No. 26705.
- Card, D. (1999). The causal effect of education on earnings. In Ashenfelter, O. and Card, D. (eds), *Handbook of Labor Economics*, vol. 3A, 1801-1863. Amsterdam: North Holland.
- Goldin, C. and Katz, L.F. (2008). *The Race between Education and Technology.* Cambridge, MA: Harvard University Press.
- Hanson, M. (2026). Student loan debt statistics. Education Data Initiative. https://educationdata.org/student-loan-debt-statistics
- Jepsen, C., Troske, K. and Coomes, P. (2014). The labor-market returns to community college degrees, diplomas, and certificates. *Journal of Labor Economics*, 32(1), 95-121.
- Kim, C.H. and Tamborini, C.R. (2019). Are they still worth it? The long-run earnings benefits of an associate degree, vocational diploma or certificate, and some college. *RSF: The Russell Sage Foundation Journal of the Social Sciences*, 5(3), 64-85.
- Ruggles, S., Flood, S., Sobek, M., Backman, D., Chen, A., Cooper, G., Richards, S., Rogers, R. and Schouweiler, M. (2024). *IPUMS USA: Version 15.0* [dataset]. Minneapolis, MN: IPUMS. https://doi.org/10.18128/D010.V15.0
- U.S. Department of Education, Federal Student Aid (2026). Interest rates for Federal Direct Loans first disbursed between July 1, 2026, and June 30, 2027. Electronic Announcement GENERAL-26-33.
- Zhang, G., Jabbari, J., Despard, M., Mei, X., Chun, Y. and Roll, S. (2025). Beyond earnings premia: debt-adjusted returns to postsecondary education. SSRN Working Paper.
