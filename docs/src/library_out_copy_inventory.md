# Allocating image kernels

The following registered operators retain a `# out: copy` path. They accept
`out`, overwrite it fully, and preserve results, but still allocate their kernel
result. Names shared by several bundles are listed once with all those bundles.
The six basic 2D morphology operators use genuine `!` kernels for matching
storage types; their copy path applies to mixed storage. `morphogradient_2D`
and `morpholaplace_2D` retain copy paths for every storage type.

Direct paths cover 2D arithmetic and scalar arithmetic, constants, identity,
inversion, inverse-log and power transforms, RGB arithmetic/channel operations,
RGB adjustments/statistics/masking, volume constants/casts, volume arithmetic,
Boolean logic, inversion, and gamma. This inventory excludes those paths.

**`bundle_image2DBinary_basic_factory`**

`experimental_tobinary_image2D`, `experimental_tobinary_th_image2D_factory`.

**`bundle_image2DBinary_binarize_factory`**

`binarize_adaptive2D`, `binarize_niblack2D`, `binarize_polysegment2D`, `binarize_sauvola2D`, `binarize_otsu2D`, `binarize_minimumintermodes2D`, `binarize_intermodes2D`, `binarize_minimumerror2D`, `binarize_moments2D`, `binarize_unimodalrosin2D`, `binarize_entropy2D`, `binarize_balanced2D`, `binarize_yen2D`, `binarize_manual2D`.

**`bundle_image2DBinary_blob_extraction_factory`**

`blob_extraction_largest_blob`, `blob_extraction_smallest_blob`, `blob_extraction_longest_horizontally_blob`, `blob_extraction_shortest_horizontally_blob`, `blob_extraction_longest_vertically_blob`, `blob_extraction_shortest_vertically_blob`, `blob_extraction_size_between_blob`, `blob_extraction_max_mean_blob`, `blob_extraction_max_median_blob`, `blob_extraction_max_std_blob`, `blob_extraction_max_max_blob`, `blob_extraction_max_min_blob`, `blob_extraction_min_mean_blob`, `blob_extraction_min_median_blob`, `blob_extraction_min_std_blob`, `blob_extraction_min_max_blob`, `blob_extraction_min_min_blob`.

**`bundle_image2DBinary_filtering_factory`**

`sobelx_image2D`, `sobely_image2D`, `sobelm_image2D`, `ando3x_image2D`, `ando3y_image2D`, `ando3m_image2D`, `ando4x_image2D`, `ando4y_image2D`, `ando4m_image2D`, `ando5x_image2D`, `ando5y_image2D`, `ando5m_image2D`, `bickleyx_image2D`, `bickleyy_image2D`, `bickleym_image2D`, `prewittx_image2D`, `prewitty_image2D`, `prewittm_image2D`, `scharrx_image2D`, `scharry_image2D`, `scharrm_image2D`, `gaussian5_image2D`, `gaussian9_image2D`, `gaussian13_image2D`, `gaussian17_image2D`, `gaussian25_image2D`, `laplacian3_image2D`, `dog_image2D`, `moffat5_image2D`, `moffat13_image2D`, `moffat25_image2D`, `findlocalminima_image2D`, `findlocalmaxima_image2D`.

**`bundle_image2DBinary_foreground_extraction_factory`**

`boykov_jolly_foreground`, `grabcut_foreground`.

**`bundle_image2DBinary_fromVolume_factory`**

`proj_any_y`, `proj_all_y`, `slice_center_y`, `slice_at_y`, `slice_largest_y`, `proj_any_x`, `proj_all_x`, `slice_center_x`, `slice_at_x`, `slice_largest_x`, `proj_any_z`, `proj_all_z`, `slice_center_z`, `slice_at_z`, `slice_largest_z`.

**`bundle_image2DBinary_maskshape_factory`**

`shape_fill_holes`, `shape_holes`, `shape_convex_hull`, `shape_convex_hull_objects`, `shape_bbox_fill`, `shape_skeleton`, `shape_boundary`, `shape_remove_small`, `shape_remove_large`, `shape_clear_border`, `shape_keep_border`, `shape_majority`.

**`bundle_image2DBinary_morph_factory`, `bundle_image2DIntensity_morph_factory`**

`erosion_2D`, `dilation_2D`, `opening_2D`, `closing_2D`, `tophat_2D`, `bothat_2D`, `morphogradient_2D`, `morpholaplace_2D`.

**`bundle_image2DBinary_pool_factory`, `bundle_image2DIntensity_pool_factory`, `bundle_image2DSegment_pool_factory`**

`avgpool_blocks`, `avgpool_cross_blocks`, `maxpool_blocks`, `maxpool_cross_blocks`, `minpool_blocks`, `minpool_cross_blocks`.

**`bundle_image2DBinary_pooler_factory`, `bundle_image2DIntensity_pooler_factory`, `bundle_image2DSegment_pooler_factory`**

`meanpool`, `maxpool`, `minpool`, `stdpool`, `medianpool`, `uniquecountpool`, `argmaxcountpool`, `argmincountpool`, `iqrpool`.

**`bundle_image2DBinary_transform_factory`, `bundle_image2DIntensity_transform_factory`, `bundle_image2DSegment_transform_factory`**

`transform_flip_h`, `transform_flip_v`, `transform_rotate_180`, `transform_rotate_90`, `transform_rotate_270`, `transform_rotate`, `transform_shift`, `transform_shift_wrap`, `transform_flip_h_if_right`, `transform_flip_v_if_bottom`, `transform_align_axis`, `transform_canonical_pose`.

**`bundle_image2DBinary_zoom_factory`, `bundle_image2DSegment_zoom_factory`**

`zoom_crop_bbox`, `zoom_crop_bbox_largest`, `zoom_crop_bbox_smallest`, `zoom_crop_bbox_most_elongated`, `zoom_crop_bbox_least_elongated`, `zoom_crop_bbox_most_circular`, `zoom_crop_bbox_least_circular`, `zoom_crop_bbox_most_rectangular`, `zoom_crop_bbox_least_rectangular`, `zoom_crop_bbox_widest`, `zoom_crop_bbox_narrowest`, `zoom_crop_bbox_tallest`, `zoom_crop_bbox_shortest`, `zoom_crop_bbox_topmost`, `zoom_crop_bbox_bottommost`, `zoom_crop_bbox_leftmost`, `zoom_crop_bbox_rightmost`, `zoom_crop_bbox_most_central`, `zoom_crop_bbox_most_peripheral`, `zoom_crop_bbox_most_isolated`, `zoom_crop_bbox_least_isolated`, `zoom_crop_bbox_second_largest`, `zoom_crop_aspect`, `zoom_crop_aspect_largest`, `zoom_crop_aspect_smallest`, `zoom_crop_aspect_most_elongated`, `zoom_crop_aspect_least_elongated`, `zoom_crop_aspect_most_circular`, `zoom_crop_aspect_least_circular`, `zoom_crop_aspect_most_rectangular`, `zoom_crop_aspect_least_rectangular`, `zoom_crop_aspect_widest`, `zoom_crop_aspect_narrowest`, `zoom_crop_aspect_tallest`, `zoom_crop_aspect_shortest`, `zoom_crop_aspect_topmost`, `zoom_crop_aspect_bottommost`, `zoom_crop_aspect_leftmost`, `zoom_crop_aspect_rightmost`, `zoom_crop_aspect_most_central`, `zoom_crop_aspect_most_peripheral`, `zoom_crop_aspect_most_isolated`, `zoom_crop_aspect_least_isolated`, `zoom_crop_aspect_second_largest`, `zoom_crop_isolate`, `zoom_crop_isolate_largest`, `zoom_crop_isolate_smallest`, `zoom_crop_isolate_most_elongated`, `zoom_crop_isolate_least_elongated`, `zoom_crop_isolate_most_circular`, `zoom_crop_isolate_least_circular`, `zoom_crop_isolate_most_rectangular`, `zoom_crop_isolate_least_rectangular`, `zoom_crop_isolate_widest`, `zoom_crop_isolate_narrowest`, `zoom_crop_isolate_tallest`, `zoom_crop_isolate_shortest`, `zoom_crop_isolate_topmost`, `zoom_crop_isolate_bottommost`, `zoom_crop_isolate_leftmost`, `zoom_crop_isolate_rightmost`, `zoom_crop_isolate_most_central`, `zoom_crop_isolate_most_peripheral`, `zoom_crop_isolate_most_isolated`, `zoom_crop_isolate_least_isolated`, `zoom_crop_isolate_second_largest`, `zoom_recenter`, `zoom_recenter_largest`, `zoom_recenter_smallest`, `zoom_recenter_most_elongated`, `zoom_recenter_least_elongated`, `zoom_recenter_most_circular`, `zoom_recenter_least_circular`, `zoom_recenter_most_rectangular`, `zoom_recenter_least_rectangular`, `zoom_recenter_widest`, `zoom_recenter_narrowest`, `zoom_recenter_tallest`, `zoom_recenter_shortest`, `zoom_recenter_topmost`, `zoom_recenter_bottommost`, `zoom_recenter_leftmost`, `zoom_recenter_rightmost`, `zoom_recenter_most_central`, `zoom_recenter_most_peripheral`, `zoom_recenter_most_isolated`, `zoom_recenter_least_isolated`, `zoom_recenter_second_largest`, `zoom_glimpse_10p`, `zoom_glimpse_25p`, `zoom_glimpse_50p`, `zoom_recenter_point`, `zoom_center`, `zoom_rows`, `zoom_cols`.

**`bundle_image2DIntensity_basic_factory`**

`experimental_normalize_2D`, `experimental_standardize_2D`, `experimental_tointensity_image2D`.

**`bundle_image2DIntensity_blob_extraction_factory`**

`blob_extraction_largest`, `blob_extraction_smallest`, `blob_extraction_longest_horizontally`, `blob_extraction_shortest_horizontally`, `blob_extraction_longest_vertically`, `blob_extraction_shortest_vertically`, `blob_extraction_max_mean`, `blob_extraction_max_median`, `blob_extraction_max_std`, `blob_extraction_max_max`, `blob_extraction_max_min`, `blob_extraction_min_mean`, `blob_extraction_min_median`, `blob_extraction_min_std`, `blob_extraction_min_max`, `blob_extraction_min_min`.

**`bundle_image2DIntensity_filtering_factory`**

`sobelx_image2D`, `sobely_image2D`, `sobelm_image2D`, `ando3x_image2D`, `ando3y_image2D`, `ando3m_image2D`, `ando4x_image2D`, `ando4y_image2D`, `ando4m_image2D`, `ando5x_image2D`, `ando5y_image2D`, `ando5m_image2D`, `bickleyx_image2D`, `bickleyy_image2D`, `bickleym_image2D`, `prewittx_image2D`, `prewitty_image2D`, `prewittm_image2D`, `scharrx_image2D`, `scharry_image2D`, `scharrm_image2D`, `gaussian5_image2D`, `gaussian9_image2D`, `gaussian13_image2D`, `gaussian17_image2D`, `gaussian25_image2D`, `laplacian3_image2D`, `dog_image2D`, `moffat5_image2D`, `moffat13_image2D`, `moffat25_image2D`.

**`bundle_image2DIntensity_foreground_extraction_factory`**

`random_walker_foreground`, `closed_form_matting`.

**`bundle_image2DIntensity_fromVolume_factory`**

`proj_max_y`, `proj_min_y`, `proj_mean_y`, `proj_std_y`, `proj_argmax_y`, `slice_center_y`, `slice_brightest_y`, `slice_at_y`, `proj_max_masked_y`, `proj_mean_masked_y`, `slice_centroid_y`, `slice_largest_y`, `proj_max_x`, `proj_min_x`, `proj_mean_x`, `proj_std_x`, `proj_argmax_x`, `slice_center_x`, `slice_brightest_x`, `slice_at_x`, `proj_max_masked_x`, `proj_mean_masked_x`, `slice_centroid_x`, `slice_largest_x`, `proj_max_z`, `proj_min_z`, `proj_mean_z`, `proj_std_z`, `proj_argmax_z`, `slice_center_z`, `slice_brightest_z`, `slice_at_z`, `proj_max_masked_z`, `proj_mean_masked_z`, `slice_centroid_z`, `slice_largest_z`.

**`bundle_image2DIntensity_maskshape_factory`**

`shape_distance_inside`, `shape_proximity`.

**`bundle_image2DIntensity_orientation_factory`**

`grad_magnitude`, `grad_orientation`, `orientation_select`.

**`bundle_image2DIntensity_saliency_fixation_factory`**

`itti_koch_saliency`, `spectral_residual_saliency`.

**`bundle_image2DIntensity_transcendental_factory`**

`exp_image2D`, `log_image2D`.

**`bundle_image2DIntensity_zoom_factory`**

`zoom_crop_bbox`, `zoom_crop_bbox_largest`, `zoom_crop_bbox_smallest`, `zoom_crop_bbox_most_elongated`, `zoom_crop_bbox_least_elongated`, `zoom_crop_bbox_most_circular`, `zoom_crop_bbox_least_circular`, `zoom_crop_bbox_most_rectangular`, `zoom_crop_bbox_least_rectangular`, `zoom_crop_bbox_widest`, `zoom_crop_bbox_narrowest`, `zoom_crop_bbox_tallest`, `zoom_crop_bbox_shortest`, `zoom_crop_bbox_topmost`, `zoom_crop_bbox_bottommost`, `zoom_crop_bbox_leftmost`, `zoom_crop_bbox_rightmost`, `zoom_crop_bbox_most_central`, `zoom_crop_bbox_most_peripheral`, `zoom_crop_bbox_most_isolated`, `zoom_crop_bbox_least_isolated`, `zoom_crop_bbox_second_largest`, `zoom_crop_bbox_brightest`, `zoom_crop_bbox_darkest`, `zoom_crop_aspect`, `zoom_crop_aspect_largest`, `zoom_crop_aspect_smallest`, `zoom_crop_aspect_most_elongated`, `zoom_crop_aspect_least_elongated`, `zoom_crop_aspect_most_circular`, `zoom_crop_aspect_least_circular`, `zoom_crop_aspect_most_rectangular`, `zoom_crop_aspect_least_rectangular`, `zoom_crop_aspect_widest`, `zoom_crop_aspect_narrowest`, `zoom_crop_aspect_tallest`, `zoom_crop_aspect_shortest`, `zoom_crop_aspect_topmost`, `zoom_crop_aspect_bottommost`, `zoom_crop_aspect_leftmost`, `zoom_crop_aspect_rightmost`, `zoom_crop_aspect_most_central`, `zoom_crop_aspect_most_peripheral`, `zoom_crop_aspect_most_isolated`, `zoom_crop_aspect_least_isolated`, `zoom_crop_aspect_second_largest`, `zoom_crop_aspect_brightest`, `zoom_crop_aspect_darkest`, `zoom_crop_isolate`, `zoom_crop_isolate_largest`, `zoom_crop_isolate_smallest`, `zoom_crop_isolate_most_elongated`, `zoom_crop_isolate_least_elongated`, `zoom_crop_isolate_most_circular`, `zoom_crop_isolate_least_circular`, `zoom_crop_isolate_most_rectangular`, `zoom_crop_isolate_least_rectangular`, `zoom_crop_isolate_widest`, `zoom_crop_isolate_narrowest`, `zoom_crop_isolate_tallest`, `zoom_crop_isolate_shortest`, `zoom_crop_isolate_topmost`, `zoom_crop_isolate_bottommost`, `zoom_crop_isolate_leftmost`, `zoom_crop_isolate_rightmost`, `zoom_crop_isolate_most_central`, `zoom_crop_isolate_most_peripheral`, `zoom_crop_isolate_most_isolated`, `zoom_crop_isolate_least_isolated`, `zoom_crop_isolate_second_largest`, `zoom_crop_isolate_brightest`, `zoom_crop_isolate_darkest`, `zoom_recenter`, `zoom_recenter_largest`, `zoom_recenter_smallest`, `zoom_recenter_most_elongated`, `zoom_recenter_least_elongated`, `zoom_recenter_most_circular`, `zoom_recenter_least_circular`, `zoom_recenter_most_rectangular`, `zoom_recenter_least_rectangular`, `zoom_recenter_widest`, `zoom_recenter_narrowest`, `zoom_recenter_tallest`, `zoom_recenter_shortest`, `zoom_recenter_topmost`, `zoom_recenter_bottommost`, `zoom_recenter_leftmost`, `zoom_recenter_rightmost`, `zoom_recenter_most_central`, `zoom_recenter_most_peripheral`, `zoom_recenter_most_isolated`, `zoom_recenter_least_isolated`, `zoom_recenter_second_largest`, `zoom_recenter_brightest`, `zoom_recenter_darkest`, `zoom_glimpse_10p`, `zoom_glimpse_25p`, `zoom_glimpse_50p`, `zoom_recenter_point`, `zoom_center`, `zoom_rows`, `zoom_cols`.

**`bundle_image2DSegment_basic_factory`**

`experimental_tosegment_image2D`.

**`bundle_image2DSegment_segmentation_factory`**

`fastscanning_image2D`, `watershed_image2D`.

**`bundle_image3DBinary_volume_factory`**

`vol_threshold`, `vol_otsu`, `vol_top_fraction`, `vol_erode`, `vol_dilate`, `vol_open`, `vol_close`, `vol_morph_gradient`, `vol_erode_cross`, `vol_dilate_cross`, `vol_fill_holes`, `vol_holes`, `vol_largest_component`, `vol_central_component`, `vol_remove_small`, `vol_clear_border`, `vol_majority`, `vol_bbox_fill`, `vol_flip_y`, `vol_flip_x`, `vol_flip_z`, `vol_rot90_xy`, `vol_rot90_xz`, `vol_rot90_yz`, `vol_shift_y`, `vol_shift_x`, `vol_shift_z`, `vol_crop_bbox`, `vol_crop_bbox_largest`, `vol_recenter`, `vol_recenter_largest`, `vol_extrude_y`, `vol_mask2d_y`, `vol_extrude_x`, `vol_mask2d_x`, `vol_extrude_z`, `vol_mask2d_z`.

**`bundle_image3DIntensity_rgb_composition_factory`**

`compose_rgb`, `gray_to_rgb`, `replace_red_rgb`, `replace_green_rgb`, `replace_blue_rgb`, `multiply_rgb_intensity`, `alpha_blend_rgb`, `set_luminance_rgb`.

**`bundle_image3DIntensity_spatial_rgb_factory`**

`sobel_magnitude_rgb`, `laplacian_magnitude_rgb`, `gaussian_blur_rgb`, `difference_of_gaussians_rgb`, `unsharp_mask_rgb`, `local_contrast_normalize_rgb`, `local_std_rgb`, `gabor_energy_rgb`.

**`bundle_image3DIntensity_volume_factory`**

`vol_gaussian`, `vol_gaussian_s05`, `vol_gaussian_s1`, `vol_gaussian_s2`, `vol_mean_3`, `vol_mean_5`, `vol_gradient`, `vol_laplacian`, `vol_dog`, `vol_local_std`, `vol_unsharp`, `vol_normalize`, `vol_robust_normalize`, `vol_equalize`, `vol_threshold_zero`, `vol_erode`, `vol_dilate`, `vol_open`, `vol_close`, `vol_morph_gradient`, `vol_tophat`, `vol_bothat`, `vol_erode_cross`, `vol_dilate_cross`, `vol_window`, `vol_mask_keep`, `vol_mask_zero`, `vol_distance_inside`, `vol_proximity`, `vol_flip_y`, `vol_flip_x`, `vol_flip_z`, `vol_rot90_xy`, `vol_rot90_xz`, `vol_rot90_yz`, `vol_shift_y`, `vol_shift_x`, `vol_shift_z`, `vol_crop_bbox`, `vol_crop_bbox_largest`, `vol_recenter`, `vol_recenter_largest`, `vol_extrude_y`, `vol_mask2d_y`, `vol_extrude_x`, `vol_mask2d_x`, `vol_extrude_z`, `vol_mask2d_z`.

**`experimental_bundle_image2D_mask_factory`**

`maskgt_image2D`, `masklt_image2D`, `maskeqt_image2D`, `experimental_notmaskbycolor_image2D`.

**`experimental_bundle_image2D_maskregion_factory`**

`experimental_notmaskfromtov_image2D`, `experimental_notmaskfromtoh_image2D`, `experimental_maskfromtov_image2D`, `experimental_maskfromtoh_image2D`.

**`experimental_bundle_image2D_maskregion_relative_factory`**

`experimental_notmaskfromtov_relative_image2D`, `experimental_notmaskfromtoh_relative_image2D`, `experimental_maskfromtov_relative_image2D`, `experimental_maskfromtoh_relative_image2D`, `experimental_notmaskaround_relative_image2D`.

