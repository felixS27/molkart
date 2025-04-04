# nf-core/molkart: Usage

## :warning: Please read this documentation on the nf-core website: [https://nf-co.re/molkart/usage](https://nf-co.re/molkart/usage)

> _Documentation of pipeline parameters is generated automatically from the pipeline schema and can no longer be found in markdown files._

## Introduction

## Samplesheet input

You will need to create a samplesheet with information about the samples you would like to analyse before running the pipeline. Use this parameter to specify its location. It has to be a comma-separated file with 3 columns (4th column optional), and a header row as shown in the examples below.

```bash
--input '[path to samplesheet file]'
```

### Full samplesheet

The pipeline requires that the first column specifies the sample ID. If multiple rows are provided, their sample tags must be different. The samplesheet needs to have the three column names exactly as specified below, with the optional fourth column specifying the `membrane_image` (it does not have to be a membrane image necessarily, but the second image can be provided here to help with segmentation).

A final samplesheet file that can be used to process a full dataset (after segmentation optimization), where a matching membrane image is provided would look like:

```csv title="samplesheet.csv"
sample,nuclear_image,spot_table,membrane_image
SAMPLE1,SAMPLE1.nucleus.tiff,SAMPLE1.spots.txt,SAMPLE1.membrane.tiff
SAMPLE2,SAMPLE2.nucleus.tiff,SAMPLE2.spots.txt,SAMPLE2.membrane.tiff
SAMPLE3,SAMPLE3.nucleus.tiff,SAMPLE3.spots.txt,SAMPLE3.membrane.tiff
SAMPLE4,SAMPLE4.nucleus.tiff,SAMPLE4.spots.txt,SAMPLE4.membrane.tiff
```

| Column           | Description                                                                                                                                                                        |
| ---------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `sample`         | Custom sample name. If multiple field-of-views (FOVs) are being processed for the same sample, their sample tags must be different. Must not contain spaces.                       |
| `nuclear_image`  | Full path to the nuclear stain image (DAPI, Hoechst). Must be in **TIFF** format (`.tiff` or `.tif`).                                                                              |
| `spot_table`     | Full path to the **spot table** (`.tsv` or `.txt`). The table must contain **x, y, z position columns and a gene column**, with **no header** and **tab-separated values (`\t`)**. |
| `membrane_image` | Full path to the membrane stain image (e.g., WGA) or a second channel to assist with segmentation. Must be in **TIFF** format (`.tiff` or `.tif`). _(Optional)_                    |

An [example samplesheet](../assets/samplesheet.csv) has been provided with the pipeline.

## Running the pipeline

The typical command for running the pipeline with default values is as follows:

```bash
nextflow run nf-core/molkart --input ./samplesheet.csv --outdir ./results -profile docker
```

This will launch the pipeline with the `docker` configuration profile. See below for more information about profiles.

Note that the pipeline will create the following files in your working directory:

```bash
work                # Directory containing the nextflow working files
<OUTDIR>            # Finished results in specified location (defined with --outdir)
.nextflow_log       # Log file from Nextflow
# Other nextflow hidden files, eg. history of pipeline runs and old logs.
```

If you wish to repeatedly use the same parameters for multiple runs, rather than specifying each flag in the command, you can specify these in a params file.

Pipeline settings can be provided in a `yaml` or `json` file via `-params-file <file>`.

> [!WARNING]
> Do not use `-c <file>` to specify parameters as this will result in errors. Custom config files specified with `-c` must only be used for [tuning process resource specifications](https://nf-co.re/docs/usage/configuration#tuning-workflow-resources), other infrastructural tweaks (such as output directories), or module arguments (args).

The above pipeline run specified with a params file in yaml format:

```bash
nextflow run nf-core/molkart -profile docker -params-file params.yaml
```

with:

```yaml
input: "./samplesheet.csv"
outdir: "./results"
```

Additionally, `params.yaml` can contain optional parameters:

```yaml
input: "./samplesheet.csv"
outdir: "./results"
segmentation_method: "mesmer"
segmentation_min_area: null
segmentation_max_area: null
cellpose_save_flows: false
cellpose_diameter: 30
cellpose_chan: 0
cellpose_chan2: null
cellpose_pretrained_model: "cyto"
cellpose_custom_model: null
cellpose_flow_threshold: 0.4
cellpose_edge_exclude: true
stardist_model: "2D_versatile_fluo"
stardist_n_tiles_x: 3
stardist_n_tiles_y: 3
mesmer_image_mpp: 0.138
mesmer_compartment: "whole-cell"
ilastik_pixel_project: null
ilastik_multicut_project: null
skip_mindagap: false
mindagap_tilesize: 2144
mindagap_boxsize: 3
mindagap_loopnum: 40
mindagap_edges: false
skip_clahe: false
clahe_cliplimit: 0.01
clahe_nbins: 256
clahe_pixel_size: 0.138
clahe_kernel: 25
clahe_pyramid_tile: 1072
create_training_subset: false
crop_amount: 4
crop_nonzero_fraction: 0.4
crop_size_x: 400
crop_size_y: 400
```

You can also generate such `YAML`/`JSON` files via [nf-core/launch](https://nf-co.re/launch).

### Utilizing the create training feature

To run the pipeline so that the training subset is created with default values, run the following:

```bash
nextflow run nf-core/molkart --input ./samplesheet.csv --outdir ./results -profile docker --create_training_subset
```

The number of crops, fraction of non-zero pixels in the crops, and crop size can be adjusted through parameters.
This process generates both `TIFF` and `HDF5` files that are compatible with the Cellpose and ilastik GUIs for model training. The trained models can then be fed back into the pipeline for automated processing.

After training a Cellpose model, or creating ilastik Pixel Classification and Multicut projects, make sure you match the parameters (e.g cell diameter, flow threshold) in the run to your training and continue the default pipeline run with:

```bash
nextflow run nf-core/molkart --input ./samplesheet.csv --outdir ./results -profile docker --segmentation_method cellpose,ilastik --cellpose_custom_model /path/to/model --ilastik_pixel_project /path/to/pixel_classifier.ilp --ilastik_multicut_project /path/to/multicut.ilp
```

### Segmentation approaches

The four segmentation approaches (Mesmer, Cellpose, Stardist, ilastik) can be chosen using the `segmentation_method` parameter. If multiple are given (comma-separated, no whitespace), the pipeline will apply them in parallel. For parameter-based model options, please check the original tool's documentation. These can be provided with `mesmer_compartment`, `cellpose_pretrained_model`, and `stardist_model` for Mesmer, Cellpose and Stardist respectively.

:::note
If a custom Cellpose model is provided via the `cellpose_custom_model` parameter as a path, the `cellpose_pretrained_model` parameter is ignored.
:::
:::note
Stardist segmentation currently only supports nuclear segmentation and the additional marker will not be used.
:::
:::note
Stardist is the only tool that natively supports tiling. Make sure to adapt requested resources based on the size of the input image(s).
:::
:::note
ilastik segmentation requires user-provided Pixel Classification and Multicut project files. The user must ensure that the training files have the same axes as the segmentation input files to ensure compatibility.
:::

### Skipping processes

By default, both Mindagap and CLAHE are run, however both can be skipped when running the pipeline using the `skip_mindagap` and `skip_clahe` parameters.

Local contrast enhancement might not be needed for every dataset and parameters should be chosen carefully depending on the data.

Similarly, if the data does not have the grid pattern characteristic for Molecular Cartography data, Mindagap can be skipped (e.g. for Merscope data) meaning both grid-filling and Duplicatefinder would not be applied to the data.

### Updating the pipeline

When you run the above command, Nextflow automatically pulls the pipeline code from GitHub and stores it as a cached version. When running the pipeline after this, it will always use the cached version if available - even if the pipeline has been updated since. To make sure that you're running the latest version of the pipeline, make sure that you regularly update the cached version of the pipeline:

```bash
nextflow pull nf-core/molkart
```

### Reproducibility

It is a good idea to specify the pipeline version when running the pipeline on your data. This ensures that a specific version of the pipeline code and software are used when you run your pipeline. If you keep using the same tag, you'll be running the same version of the pipeline, even if there have been changes to the code since.

First, go to the [nf-core/molkart releases page](https://github.com/nf-core/molkart/releases) and find the latest pipeline version - numeric only (eg. `1.3.1`). Then specify this when running the pipeline with `-r` (one hyphen) - eg. `-r 1.3.1`. Of course, you can switch to another version by changing the number after the `-r` flag.

This version number will be logged in reports when you run the pipeline, so that you'll know what you used when you look back in the future. For example, at the bottom of the MultiQC reports.

To further assist in reproducibility, you can use share and reuse [parameter files](#running-the-pipeline) to repeat pipeline runs with the same settings without having to write out a command with every single parameter.

> [!TIP]
> If you wish to share such profile (such as upload as supplementary material for academic publications), make sure to NOT include cluster specific paths to files, nor institutional specific profiles.

## Core Nextflow arguments

> [!NOTE]
> These options are part of Nextflow and use a _single_ hyphen (pipeline parameters use a double-hyphen)

### `-profile`

Use this parameter to choose a configuration profile. Profiles can give configuration presets for different compute environments.

Several generic profiles are bundled with the pipeline which instruct the pipeline to use software packaged using different methods (Docker, Singularity, Podman, Shifter, Charliecloud, Apptainer, Conda) - see below.

> [!IMPORTANT]
> We highly recommend the use of Docker or Singularity containers for full pipeline reproducibility, as currently for this pipeline, Conda is not supported.

The pipeline also dynamically loads configurations from [https://github.com/nf-core/configs](https://github.com/nf-core/configs) when it runs, making multiple config profiles for various institutional clusters available at run time. For more information and to check if your system is supported, please see the [nf-core/configs documentation](https://github.com/nf-core/configs#documentation).

Note that multiple profiles can be loaded, for example: `-profile test,docker` - the order of arguments is important!
They are loaded in sequence, so later profiles can overwrite earlier profiles.

If `-profile` is not specified, the pipeline will run locally and expect all software to be installed and available on the `PATH`. This is _not_ recommended, since it can lead to different results on different machines dependent on the computer environment.

- `test`
  - A profile with a complete configuration for automated testing
  - Includes links to test data so needs no other parameters
- `docker`
  - A generic configuration profile to be used with [Docker](https://docker.com/)
- `singularity`
  - A generic configuration profile to be used with [Singularity](https://sylabs.io/docs/)
- `podman`
  - A generic configuration profile to be used with [Podman](https://podman.io/)
- `shifter`
  - A generic configuration profile to be used with [Shifter](https://nersc.gitlab.io/development/shifter/how-to-use/)
- `charliecloud`
  - A generic configuration profile to be used with [Charliecloud](https://hpc.github.io/charliecloud/)
- `apptainer`
  - A generic configuration profile to be used with [Apptainer](https://apptainer.org/)
- `wave`
  - A generic configuration profile to enable [Wave](https://seqera.io/wave/) containers. Use together with one of the above (requires Nextflow ` 24.03.0-edge` or later).
- `conda`
  - A generic configuration profile to be used with [Conda](https://conda.io/docs/). Please only use Conda as a last resort i.e. when it's not possible to run the pipeline with Docker, Singularity, Podman, Shifter, Charliecloud, or Apptainer. Currently not supported.

### `-resume`

Specify this when restarting a pipeline. Nextflow will use cached results from any pipeline steps where the inputs are the same, continuing from where it got to previously. For input to be considered the same, not only the names must be identical but the files' contents as well. For more info about this parameter, see [this blog post](https://www.nextflow.io/blog/2019/demystifying-nextflow-resume.html).

You can also supply a run name to resume a specific run: `-resume [run-name]`. Use the `nextflow log` command to show previous run names.

### `-c`

Specify the path to a specific config file (this is a core Nextflow command). See the [nf-core website documentation](https://nf-co.re/usage/configuration) for more information.

## Custom configuration

### Resource requests

Whilst the default requirements set within the pipeline will hopefully work for most people and with most input data, you may find that you want to customise the compute resources that the pipeline requests. Each step in the pipeline has a default set of requirements for number of CPUs, memory and time. For most of the pipeline steps, if the job exits with any of the error codes specified [here](https://github.com/nf-core/rnaseq/blob/4c27ef5610c87db00c3c5a3eed10b1d161abf575/conf/base.config#L18) it will automatically be resubmitted with higher resources request (2 x original, then 3 x original). If it still fails after the third attempt then the pipeline execution is stopped.

To change the resource requests, please see the [max resources](https://nf-co.re/docs/usage/configuration#max-resources) and [tuning workflow resources](https://nf-co.re/docs/usage/configuration#tuning-workflow-resources) section of the nf-core website.

### Custom Containers

In some cases, you may wish to change the container or conda environment used by a pipeline steps for a particular tool. By default, nf-core pipelines use containers and software from the [biocontainers](https://biocontainers.pro/) or [bioconda](https://bioconda.github.io/) projects. However, in some cases the pipeline specified version maybe out of date.

To use a different container from the default container or conda environment specified in a pipeline, please see the [updating tool versions](https://nf-co.re/docs/usage/configuration#updating-tool-versions) section of the nf-core website.

### Custom Tool Arguments

A pipeline might not always support every possible argument or option of a particular tool used in pipeline. Fortunately, nf-core pipelines provide some freedom to users to insert additional parameters that the pipeline does not include by default.

To learn how to provide additional arguments to a particular tool of the pipeline, please see the [customising tool arguments](https://nf-co.re/docs/usage/configuration#customising-tool-arguments) section of the nf-core website.

### nf-core/configs

In most cases, you will only need to create a custom config as a one-off but if you and others within your organisation are likely to be running nf-core pipelines regularly and need to use the same settings regularly it may be a good idea to request that your custom config file is uploaded to the `nf-core/configs` git repository. Before you do this please can you test that the config file works with your pipeline of choice using the `-c` parameter. You can then create a pull request to the `nf-core/configs` repository with the addition of your config file, associated documentation file (see examples in [`nf-core/configs/docs`](https://github.com/nf-core/configs/tree/master/docs)), and amending [`nfcore_custom.config`](https://github.com/nf-core/configs/blob/master/nfcore_custom.config) to include your custom profile.

See the main [Nextflow documentation](https://www.nextflow.io/docs/latest/config.html) for more information about creating your own configuration files.

If you have any questions or issues please send us a message on [Slack](https://nf-co.re/join/slack) on the [`#configs` channel](https://nfcore.slack.com/channels/configs).

## Running in the background

Nextflow handles job submissions and supervises the running jobs. The Nextflow process must run until the pipeline is finished.

The Nextflow `-bg` flag launches Nextflow in the background, detached from your terminal so that the workflow does not stop if you log out of your session. The logs are saved to a file.

Alternatively, you can use `screen` / `tmux` or similar tool to create a detached session which you can log back into at a later time.
Some HPC setups also allow you to run nextflow within a cluster job submitted your job scheduler (from where it submits more jobs).

## Nextflow memory requirements

In some cases, the Nextflow Java virtual machines can start to request a large amount of memory.
We recommend adding the following line to your environment to limit this (typically in `~/.bashrc` or `~./bash_profile`):

```bash
NXF_OPTS='-Xms1g -Xmx4g'
```
