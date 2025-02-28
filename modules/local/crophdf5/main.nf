process CROPHDF5 {
    tag "$meta.id"
    label 'process_single'

    container 'ghcr.io/schapirolabor/molkart-local:v0.0.4'

    input:
    tuple val(meta), path(image_stack), val(num_channels)

    output:
    tuple val(meta), path("*.hdf5"), emit: ilastik_training
    tuple val(meta), path("*.txt") , emit: crop_summary
    path "versions.yml"            , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    """
    crop_hdf5.py \\
        --input ${image_stack} \\
        --output . \\
        --num_channels ${num_channels} \\
        ${args}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        molkart_crophdf5: \$(crop_hdf5.py --version)
    END_VERSIONS
    """
}
