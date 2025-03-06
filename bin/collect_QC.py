#!/usr/bin/env python
#### Written by Kresimir Bestak and Florian Wuennemann and released under the MIT license.
#### This script takes regionprops_tabe output from mcquant and the raw spot tables from Resolve bioscience as input
#### and calculates some QC metrics for masks and spot assignments
#### If png files are provided, it combines them into one

import argparse
import pandas as pd
from PIL import Image, ImageDraw, ImageFont
import os
import numpy as np


def combine_png_files(input_paths, output_path):
    print(input_paths)
    images = []
    for file_path in input_paths:
        img = Image.open(file_path)
        image_name = os.path.basename(file_path).replace(".ome", "").replace(".crop", "_crop")
        draw = ImageDraw.Draw(img)
        font_size = 50
        font = ImageFont.load_default(font_size)
        draw.text((100, 50), image_name, fill="black", font=font)
        images.append(img)

    width, height = images[0].size
    combined_image = Image.new("RGB", (width, len(images) * height))
    for i, img in enumerate(images):
        combined_image.paste(img, (0, i * height))
    combined_image.save(os.path.join(output_path, "crop_overview.png"))


def summarize_spots(spot_table):
    ## Calculate number of spots per gene
    tx_per_gene = spot_table.groupby("gene").count().reset_index()

    ## Calculate the total number of spots in spot_table
    total_spots = spot_table.shape[0]

    ## Get list of genes
    genes = spot_table["gene"].unique()

    return (tx_per_gene, total_spots, genes)


def summarize_segmasks(cellxgene_table, spots_summary):
    ## Calculate the total number of cells (rows) in cellxgene_table
    total_cells = cellxgene_table.shape[0]

    ## Calculate the average segmentation area from column Area in cellxgene_table
    avg_area = round(cellxgene_table["Area"].mean(), 2)

    ## Calculate the % of spots assigned
    ## Subset cellxgene_table for all columns with _intensity_sum in the column name and sum the column values
    spot_assign = cellxgene_table[spots_summary[2]].sum(axis=1)
    spot_assign_total = int(sum(spot_assign))
    spot_assign_per_cell = total_cells and spot_assign_total / total_cells or 0
    spot_assign_per_cell = round(spot_assign_per_cell, 2)
    # spot_assign_per_cell = spot_assign_total / total_cells
    spot_assign_percent = spot_assign_total / spots_summary[1] * 100
    spot_assign_percent = round(spot_assign_percent, 2)

    return (total_cells, avg_area, spot_assign_per_cell, spot_assign_total, spot_assign_percent)


if __name__ == "__main__":
    # Write an argparse with input options cellxgene_table, spots and output options outdir, sample_id
    parser = argparse.ArgumentParser()
    parser.add_argument("-i", "--cellxgene", help="cellxgene regionprops_table.")
    parser.add_argument("-s", "--spots", help="Resolve biosciences spot table.")
    parser.add_argument("-o", "--outdir", help="Output directory.")
    parser.add_argument("-d", "--sample_id", help="Sample ID.")
    parser.add_argument("-g", "--segmentation_method", help="Segmentation method used.")
    parser.add_argument("--filterqc", required=False, help="QC from mask filter step")
    parser.add_argument("--png_overview", nargs="+", help="Crop overview image paths")
    parser.add_argument("--version", action="version", version="0.1.0")

    args = parser.parse_args()

    if args.png_overview != None:
        combine_png_files(args.png_overview, args.outdir)

    else:
        ## Read in cellxgene_table table
        cellxgene_table = pd.read_csv(args.cellxgene, sep=",")

        ## Read in spot table
        spots = pd.read_table(args.spots, sep="\t", names=["x", "y", "z", "gene"])
        # below code had to be added to account for the spots.txt inputs if mindagap is skipped
        if (([val for val in spots.index.values] == [val for val in range(len(spots.index.values))]) == False):
            spots["gene"] = spots["z"]
            spots["z"] = spots["y"]
            spots["y"] = spots["x"]
            spots["x"] = spots.index
            spots.index = range(len(spots))
        duplicated = sum(spots.gene.str.contains("Duplicated"))
        spots = spots[~spots.gene.str.contains("Duplicated")]

        ## Pass on filterqc values
        filterqc = pd.read_csv(
            args.filterqc,
            names=["below_min_area", "below_percentage", "above_max_area", "above_percentage", "total_labels"],
            header=None,
        )

        ## Summarize spots table
        summary_spots = summarize_spots(spots)
        summary_segmentation = summarize_segmasks(cellxgene_table, summary_spots)

        ## Create pandas data frame with one row per parameter and write each value in summary_segmentation to a new row in the data frame
        summary_df = pd.DataFrame(
            columns=[
                "sample_id",
                "segmentation_method",
                "total_cells",
                "avg_area",
                "total_spots",
                "spot_assign_per_cell",
                "spot_assign_total",
                "spot_assign_percent",
                "duplicated_total",
                "labels_total",
                "labels_below_thresh",
                "labels_above_thresh",
            ]
        )
        summary_df.loc[0] = [
            ##args.sample_id,
            args.sample_id + "_" + args.segmentation_method,
            args.segmentation_method,
            summary_segmentation[0],
            summary_segmentation[1],
            summary_spots[1],
            summary_segmentation[2],
            summary_segmentation[3],
            summary_segmentation[4],
            duplicated,
            filterqc.total_labels[1],
            filterqc.below_min_area[1],
            filterqc.above_max_area[1],
        ]
        print(args.sample_id)
        # Write summary_df to a csv file
        summary_df.to_csv(
            f"{args.outdir}/{args.sample_id}.{args.segmentation_method}.spot_QC.csv", header=True, index=False
        )
