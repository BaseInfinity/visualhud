# TMNT Source Images

Place the real four-panel TMNT character-select reference here as:

```text
assets/source/tmnt/character-select.png
```

Then generate source-backed VisualHUD sprites:

```sh
python3 scripts/import-tmnt-sprites.py \
  --source assets/source/tmnt/character-select.png \
  --output-dir themes/tmnt/sprites \
  --source-label "tmnt-character-select-reference"
```

The generated `themes/tmnt/sprites/manifest.json` records source and crop
coordinates. Do not commit generated TMNT placeholder art.

## One-Off Character Sources

Some lifecycle or non-turtle states use one-off source art instead of the
four-panel character-select image. Import those with explicit character crops:

```sh
python3 scripts/import-tmnt-sprites.py \
  --asset-crop "tmnt-shredder=assets/source/tmnt/shredder-source.png=250,190,430,430" \
  --output-dir themes/tmnt/sprites \
  --source-label "shredder-character-crop-from-return-of-the-shredder-source"
```

April source:

- File: `assets/source/tmnt/april-character-source.jpg`
- Source: <https://tmnt2012series.fandom.com/wiki/1987_April_O%27Neil>
- Direct asset: <https://static.wikia.nocookie.net/tmnt2012series/images/a/a6/1987AprilO%27Neil.jpg/revision/latest?cb=20141229065054>
- License notice on source page: CC-BY-SA

Additional focused sources:

- Metalhead: `assets/source/tmnt/metalhead-character-source.png`
  Source: <https://tmnt2012series.fandom.com/wiki/Metalhead>
- Splinter: `assets/source/tmnt/splinter-character-source.png`
  Source: <https://hero.fandom.com/wiki/Splinter_(Teenage_Mutant_Ninja_Turtles)>
- Krang: `assets/source/tmnt/krang-character-source.jpg`
  Source: <https://tmnt2012series.fandom.com/wiki/Krang>
- Foot Soldiers: `assets/source/tmnt/foot-soldiers-character-source.png`
  Source: <https://turtlepedia.fandom.com/wiki/Foot_Soldiers_(1987_TV_series)>
- Mutagen: `assets/source/tmnt/mutagen-object-source.jpg`
  Source: <https://turtlepedia.fandom.com/wiki/Mutagen_(1987_TV_series)>
- Casey Jones: `assets/source/tmnt/casey-jones-character-source.jpg`
  Source: <https://tmnt2012series.fandom.com/wiki/1987_Casey_Jones>
