/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES / SUBWORKFLOWS / FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

include { CROPTIFF       } from '../modules/local/croptiff/main'
include { CROPHDF5       } from '../modules/local/crophdf5/main'
include { CREATE_ANNDATA } from '../modules/local/createanndata/main'
include { CREATE_STACK   } from '../modules/local/createstack/main'
include { CLAHE          } from '../modules/local/clahe/main'
include { MASKFILTER     } from '../modules/local/maskfilter/main'
include { MOLKARTQC      } from '../modules/local/molkartqc/main'
include { MOLKARTQCPNG   } from '../modules/local/molkartqcpng/main'
include { SPOT2CELL      } from '../modules/local/spot2cell/main'
include { TIFFH5CONVERT  } from '../modules/local/tiffh5convert/main'

include { CELLPOSE                    } from '../modules/nf-core/cellpose/main'
include { DEEPCELL_MESMER             } from '../modules/nf-core/deepcell/mesmer/main'
include { ILASTIK_MULTICUT            } from '../modules/nf-core/ilastik/multicut/main'
include { ILASTIK_PIXELCLASSIFICATION } from '../modules/nf-core/ilastik/pixelclassification/main'
include { MINDAGAP_DUPLICATEFINDER    } from '../modules/nf-core/mindagap/duplicatefinder/main'
include { MINDAGAP_MINDAGAP           } from '../modules/nf-core/mindagap/mindagap/main'
include { MULTIQC                     } from '../modules/nf-core/multiqc/main'
include { STARDIST                    } from '../modules/nf-core/stardist/main'
include { paramsSummaryMultiqc        } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { softwareVersionsToYAML      } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { methodsDescriptionText      } from '../subworkflows/local/utils_nfcore_molkart_pipeline'
include { paramsSummaryMap            } from 'plugin/nf-schema'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow MOLKART {

    take:
    ch_samplesheet // channel: samplesheet read in from --input
    main:

    ch_versions = Channel.empty()
    ch_multiqc_files = Channel.empty()

    // stain: "1" denotes membrane, stain: "0" denotes nuclear image
    // this is used to preserve the order later
    membrane_tuple = ch_samplesheet
        .filter { it[3] } // filter samples with membrane
        .map {meta, _nuclear, _spots, membrane ->
            [meta + [stain: '1'], membrane]
        }

    image_tuple = ch_samplesheet
        .map {meta, nuclear, _spots, _membrane ->
            [meta + [stain: '0'], nuclear]
        }

    spot_tuple = ch_samplesheet
        .map {meta, _nuclear, spots, _membrane ->
            [meta, spots]
        }

    //
    // MODULE: Run Mindagap_mindagap
    //
    mindagap_in = membrane_tuple.mix(image_tuple) // mindagap input contains both membrane and nuclear images
    MINDAGAP_MINDAGAP(mindagap_in)
    ch_versions = ch_versions.mix(MINDAGAP_MINDAGAP.out.versions)

    //
    // MODULE: Apply Contrast-limited adaptive histogram equalization (CLAHE)
    // CLAHE is either applied to all images, or none.
    //
    clahe_in = params.skip_mindagap ? mindagap_in : MINDAGAP_MINDAGAP.out.tiff
    CLAHE(clahe_in)
    ch_versions = ch_versions.mix(CLAHE.out.versions)

    map_for_stacks = params.skip_clahe ? clahe_in : CLAHE.out.img_clahe

    map_for_stacks
        .map { meta, tiff ->
            [ meta.subMap("id"), tiff, meta.stain ]
        }
        .groupTuple(by: 0)
        .map { id, tiffs, stains ->
            def sorted = [tiffs, stains].transpose().sort { it[1] }
            def nuclear = sorted[0]
            def membrane = sorted.size() > 1 ? sorted[1] : null
            membrane ? [id, nuclear[0], membrane[0]] : [id, nuclear[0]]
        }
        .set{ grouped_map_stack }

    grouped_map_stack.filter { !it[2] } // for rows without a present membrane image, set channel to no_stack
        .set{ no_stack }

    grouped_map_stack.filter{ it[2] }      // for rows where the membrane image is present, create a list of images to be stacked
        .map{
            id, nuclear, membrane ->
            [id, tuple(nuclear, membrane)]
        }.set{ create_stack_in }

    grouped_map_stack.map{
        [it[0], it[1]]
    }.set{ nuclear_only } // for segmentation options that only accept one channel

    //
    // MODULE: Stack channels if membrane image provided for segmentation
    //
    CREATE_STACK(create_stack_in)
    ch_versions = ch_versions.mix(CREATE_STACK.out.versions)
    stack_mix = no_stack.mix(CREATE_STACK.out.stack)

    if ( params.create_training_subset ) {
        // Create subsets of the image for training an ilastik model
        stack_mix.join(
            grouped_map_stack.map{
                it[2] == null ? tuple(it[0], 1) : tuple(it[0], 2)
            } // hardcodes that if membrane channel present, num_channels is 2, otherwise 1
        ).set{ training_in }

        CROPHDF5(training_in)
        ch_versions = ch_versions.mix(CROPHDF5.out.versions)
        // Combine images with crop_summary for making the same training tiff stacks as ilastik
        tiff_crop = stack_mix.join(CROPHDF5.out.crop_summary)
        CROPTIFF(tiff_crop)
        ch_versions = ch_versions.mix(CROPTIFF.out.versions)
        MOLKARTQCPNG(CROPTIFF.out.overview.map{
                    tuple('matchkey', it[1])
                    }.groupTuple().map{ it[1]} )
        ch_versions = ch_versions.mix(MOLKARTQCPNG.out.versions)
    } else {

    //
    // MODULE: MINDAGAP Duplicatefinder
    //
    // Filter out potential duplicate spots from the spots table
    MINDAGAP_DUPLICATEFINDER(spot_tuple)
    ch_versions = ch_versions.mix(MINDAGAP_DUPLICATEFINDER.out.versions)

    qc_spots = params.skip_mindagap ? spot_tuple : MINDAGAP_DUPLICATEFINDER.out.marked_dups_spots
    //
    // MODULE: DeepCell Mesmer segmentation
    //
    segmentation_masks = Channel.empty()
    if (params.segmentation_method.split(',').contains('mesmer')) {
        DEEPCELL_MESMER(
            grouped_map_stack.map{ tuple(it[0], it[1]) },
            grouped_map_stack.map{
                it[2] == null ? [[:],[]] : tuple(it[0], it[2]) // if no membrane channel specified, give empty membrane input; if membrane image exists, provide it to the process
            }
        )
        ch_versions = ch_versions.mix(DEEPCELL_MESMER.out.versions)
        segmentation_masks = segmentation_masks
            .mix(DEEPCELL_MESMER.out.mask
                .combine(Channel.of('mesmer')))
    }
    //
    // MODULE: Stardist segmentation
    //
    if (params.segmentation_method.split(',').contains('stardist')) {
        STARDIST(
            nuclear_only,
            )
        ch_versions = ch_versions.mix(STARDIST.out.versions)
        segmentation_masks = segmentation_masks
            .mix(STARDIST.out.mask
                .combine(Channel.of('stardist')))
    }
    //
    // MODULE: Cellpose segmentation
    //
    cellpose_custom_model = params.cellpose_custom_model ? stack_mix.combine(Channel.fromPath(params.cellpose_custom_model)) : []
    if (params.segmentation_method.split(',').contains('cellpose')) {
        CELLPOSE(
            stack_mix,
            cellpose_custom_model ? cellpose_custom_model.map{it[2]} : []
            )
        ch_versions = ch_versions.mix(CELLPOSE.out.versions)
        segmentation_masks = segmentation_masks
            .mix(CELLPOSE.out.mask
                .combine(Channel.of('cellpose')))
    }
    //
    // MODULE: ilastik segmentation
    //
    if (params.segmentation_method.split(',').contains('ilastik')) {
        if (params.ilastik_pixel_project == null) {
            error "ILASTIK_PIXELCLASSIFICATION module was not provided with the project .ilp file."
        }
        stack_mix.join(
            grouped_map_stack.map{
                it[2] == null ? tuple(it[0], 1) : tuple(it[0], 2)
            }).set{ tiffin }

        TIFFH5CONVERT(tiffin)
        ch_versions = ch_versions.mix(TIFFH5CONVERT.out.versions)

        TIFFH5CONVERT.out.hdf5.combine(
            Channel.fromPath(params.ilastik_pixel_project)
            ).set{ ilastik_in }
        ILASTIK_PIXELCLASSIFICATION(
            ilastik_in.map{ [it[0], it[1]] },
            ilastik_in.map{ [it[0], it[2]] }
        )
        ch_versions = ch_versions.mix(ILASTIK_PIXELCLASSIFICATION.out.versions)

        if (params.ilastik_multicut_project == null) {
            error "ILASTIK_MULTICUT module was not provided with the project .ilp file."
        }
        ilastik_in.join(ILASTIK_PIXELCLASSIFICATION.out.output)
            .combine(Channel.fromPath(params.ilastik_multicut_project))
            .set{ multicut_in }

        ILASTIK_MULTICUT(
            multicut_in.map{ tuple(it[0], it[1]) },
            multicut_in.map{ tuple(it[0], it[4]) },
            multicut_in.map{ tuple(it[0], it[3]) }
        )
        ch_versions = ch_versions.mix(ILASTIK_MULTICUT.out.versions)
        segmentation_masks = segmentation_masks
            .mix(ILASTIK_MULTICUT.out.out_tiff
                .combine(Channel.of('ilastik')))
    }
    segmentation_masks.map{
        meta, mask, segmentation ->
        def new_meta = meta.clone()
        new_meta.segmentation = segmentation
        [new_meta, mask]
    }.set { matched_segmasks }

    //
    // MODULE: filter segmentation masks
    //
    MASKFILTER(matched_segmasks)
    ch_versions = ch_versions.mix(MASKFILTER.out.versions)
    MASKFILTER.out.filtered_mask.map{
        meta, mask ->
        tuple(meta.subMap("id"), mask, meta.segmentation)
    }.set { filtered_masks }

    //
    // MODULE: assign spots to segmentation mask
    //
    qc_spots
        .combine(filtered_masks, by: 0)
        .map {
            meta, spots_table, mask, segmethod ->
            def new_meta = meta.clone()
            new_meta.segmentation = segmethod
            [new_meta, spots_table, mask]
            }
        .set { dedup_spots }
    SPOT2CELL(dedup_spots)
    ch_versions = ch_versions.mix(SPOT2CELL.out.versions)

    //
    // MODULE: create anndata squidpy object from spot2cell table
    //
    CREATE_ANNDATA(
        SPOT2CELL.out.cellxgene_table
    )
    ch_versions = ch_versions.mix(CREATE_ANNDATA.out.versions)

    //
    // MODULE: MOLKARTQC
    //
    SPOT2CELL.out.cellxgene_table.combine(
            MASKFILTER.out.filtered_qc, by: 0
        ).map{
            meta, quant, filterqc ->
            [meta.subMap("id"), quant, meta.segmentation, filterqc]
        }.set { spot2cell_out }

    qc_spots
        .combine(spot2cell_out, by: 0)
        .set{ molkartqc }
    MOLKARTQC(molkartqc)
    ch_versions = ch_versions.mix(MOLKARTQC.out.versions)

    }

    //
    // Collate and save software versions
    //
    softwareVersionsToYAML(ch_versions)
        .collectFile(
            storeDir: "${params.outdir}/pipeline_info",
            name: 'nf_core_'  +  'molkart_software_'  + 'mqc_'  + 'versions.yml',
            sort: true,
            newLine: true
        ).set { ch_collated_versions }


    //
    // MODULE: MultiQC
    //
    ch_multiqc_config        = Channel.fromPath(
        "$projectDir/assets/multiqc_config.yml", checkIfExists: true)
    ch_multiqc_custom_config = params.multiqc_config ?
        Channel.fromPath(params.multiqc_config, checkIfExists: true) :
        Channel.empty()
    ch_multiqc_logo          = params.multiqc_logo ?
        Channel.fromPath(params.multiqc_logo, checkIfExists: true) :
        Channel.fromPath("$projectDir/assets/nf-core-molkart_logo_light.png", checkIfExists: true)

    summary_params      = paramsSummaryMap(
        workflow, parameters_schema: "nextflow_schema.json")
    ch_workflow_summary = Channel.value(paramsSummaryMultiqc(summary_params))
    ch_multiqc_files = ch_multiqc_files.mix(
        ch_workflow_summary.collectFile(name: 'workflow_summary_mqc.yaml'))
    ch_multiqc_custom_methods_description = params.multiqc_methods_description ?
        file(params.multiqc_methods_description, checkIfExists: true) :
        file("$projectDir/assets/methods_description_template.yml", checkIfExists: true)
    ch_methods_description                = Channel.value(
        methodsDescriptionText(ch_multiqc_custom_methods_description))

    ch_multiqc_files = ch_multiqc_files.mix(ch_collated_versions)
    ch_multiqc_files = ch_multiqc_files.mix(
        ch_methods_description.collectFile(
            name: 'methods_description_mqc.yaml',
            sort: true
        )
    )
    if ( params.create_training_subset ){
        ch_multiqc_files = ch_multiqc_files.mix(
            MOLKARTQCPNG.out.png_overview
            .collectFile(name: "crop_overview.png", storeDir: "${params.outdir}/multiqc" ))
        ch_multiqc_files = ch_multiqc_files.mix(
            CROPHDF5.out.crop_summary.map{it[1]}
            .collectFile(name: 'crop_overview.txt', storeDir: "${params.outdir}/multiqc")
        )
    } else {
        ch_multiqc_files = ch_multiqc_files.mix(
            MOLKARTQC.out.qc.map{it[1]}
            .collectFile())
    }

    MULTIQC (
        ch_multiqc_files.collect(),
        ch_multiqc_config.toList(),
        ch_multiqc_custom_config.toList(),
        ch_multiqc_logo.toList(),
        [],
        []
    )

    emit:multiqc_report = MULTIQC.out.report.toList() // channel: /path/to/multiqc_report.html
    versions       = ch_versions                 // channel: [ path(versions.yml) ]

}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
