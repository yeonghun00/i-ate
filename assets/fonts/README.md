# Fonts

This folder contains custom font assets for the app.

## Current fonts:
- NotoSans (already configured in theme)

## Adding new fonts:
1. Place font files (.ttf or .otf) in this folder
2. Update pubspec.yaml:
```yaml
fonts:
  - family: CustomFont
    fonts:
      - asset: assets/fonts/CustomFont-Regular.ttf
      - asset: assets/fonts/CustomFont-Bold.ttf
        weight: 700
```
3. Use in theme or widgets:
```dart
TextStyle(
  fontFamily: 'CustomFont',
  fontSize: 16,
)
```

## File naming convention:
- Use the font family name: `NotoSans-Regular.ttf`
- Include weight: `NotoSans-Bold.ttf`
- Include style: `NotoSans-Italic.ttf`