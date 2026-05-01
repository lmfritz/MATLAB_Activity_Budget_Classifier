# MATLAB Activity Budget Classifier

MATLAB scripts for classifying humpback whale tag deployments into five behavioral states and summarizing activity budgets.

## Main behavioral states

- `1` = surface active
- `2` = resting
- `3` = traveling
- `4` = foraging
- `5` = exploring

## Main scripts

- `behavior_classifier_v3.m`
  Main classifier. Loads a PRH file, detects dives and lunges, applies resting and travel logic, assigns behavioral state, and exports activity-budget and context outputs.

- `auto_activity_budget_from_prh_v3.m`
  Non-interactive wrapper for running `behavior_classifier_v3.m` on a single deployment.

- `batch_activity_budgets_v3.m`
  Batch runner for processing many PRH files and writing combined outputs.

- `build_kmeans_dive_features.m`
  Builds dive-level feature tables for clustering and QC.

- `build_kmeans_surface_features.m`
  Builds surface-bout feature tables for clustering and QC.

- `batch_surface_interval_features.m`
  Generates surface-interval summaries across deployments.

## Current classifier notes

- Dive threshold: `5 m`
- Minimum kept dive duration: `30 s`
- Post-dive carryover: `20 s`
- Resting thresholds: pooled thresholds enabled in `behavior_classifier_v3.m`
- Shallow / near-threshold lunges can be labeled as foraging with a local time buffer

## Typical workflow

1. Open or run `behavior_classifier_v3.m` for one deployment and inspect the interactive plot.
2. Use `auto_activity_budget_from_prh_v3.m` for single-deployment scripted runs.
3. Use `batch_activity_budgets_v3.m` once the classifier settings are stable.
4. Commit meaningful classifier changes to Git before and after major threshold or logic updates.

## Git workflow

Repository location on this machine:

`/Volumes/CATS/CATS/CATSMatlabTools/Activity Budget Specific Scripts`

Common commands:

```bash
git status
git add .
git commit -m "Describe the change"
git push
```

## Outputs commonly written by the classifier

- `*_AutoActivityBudget.csv`
- `*_BehaviorContextVars.mat`
- `*_BehaviorContextVars.csv`
- `*_StateSampleSummary.csv`
- `*_StateBoutSummary.csv`
- activity budget figures and interactive QC plots when enabled

