# Icons

This folder contains custom icon assets for the app.

## Organization:
- `navigation/` - Navigation bar icons
- `actions/` - Action button icons
- `status/` - Status indicator icons
- `categories/` - Category icons for different meal types
- `ui/` - General UI icons

## File naming convention:
- Use lowercase with underscores: `icon_meal_add.svg`
- Include state if needed: `icon_settings_active.svg`
- Use SVG format when possible for scalability
- PNG format for complex icons with specific colors

## Usage:
```dart
// For SVG icons
SvgPicture.asset('assets/icons/icon_meal_add.svg')

// For PNG icons
Image.asset('assets/icons/icon_settings.png')
```