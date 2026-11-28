/* SPDX-License-Identifier: GPL-3.0-only
 *
 * FreeType's module list for TinyVCMI, selected by tools/build_sdl2_addons.sh
 * with -DFT_CONFIG_MODULES_H.  VCMI 1.7.5's fonts are TrueType (Noto Sans and
 * Serif, glyf outlines; config/fonts.json), drawn by SDL_ttf solid and
 * blended, so this is the TrueType driver, the sfnt tables and glyph names it
 * reads, the auto-hinter, and the anti-aliasing and monochrome rasterisers.
 * CFF, Type 1, CID, PFR, Type 42, Windows FNT, PCF, BDF, SDF and SVG are left
 * out; a font that needs one fails to open rather than misdraws.
 */
FT_USE_MODULE( FT_Module_Class, autofit_module_class )
FT_USE_MODULE( FT_Driver_ClassRec, tt_driver_class )
FT_USE_MODULE( FT_Module_Class, sfnt_module_class )
FT_USE_MODULE( FT_Module_Class, psnames_module_class )
FT_USE_MODULE( FT_Renderer_Class, ft_smooth_renderer_class )
FT_USE_MODULE( FT_Renderer_Class, ft_raster1_renderer_class )
