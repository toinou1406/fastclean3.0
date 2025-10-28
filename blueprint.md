
# Project Blueprint: AI Photo Cleaner

## 1. Overview

This document outlines the development of a Flutter application designed to help users free up storage space on their mobile devices by intelligently identifying and deleting unnecessary photos. The core functionality relies on a local, on-device AI to analyze photos based on various criteria, ensuring user privacy and fast performance.

## 2. Core Features & Design

### Style & Design
- **UI:** Minimalist, fluid, and intuitive single-screen interface.
- **Theme:** Material 3 design with a `Colors.blue` primary swatch.
- **Layout:**
    - Top: A linear progress indicator showing used vs. total storage.
    - Center: A 3-column grid to display photos recommended for deletion.
    - Bottom: Context-aware action buttons.
- **Feedback:** Loading indicators during analysis and snack-bar notifications for success or error messages.

### Implemented Features
- **Storage Indicator:** Displays the device's storage status (`usedSpaceGB / totalSpaceGB`).
- **On-Device Photo Analysis (The "Trier" Action):**
    - Scans and analyzes user photos locally.
    - Uses a scoring system based on:
        - **Blurriness:** High score for blurry images (Laplacian variance).
        - **Darkness:** High score for overly dark images.
        - **Screenshots:** High score for images identified as screenshots by name or aspect ratio.
        - **Low Resolution:** High score for small images.
        - **Age:** High score for old photos.
        - **Duplicates & Similars:** Maximum score for exact duplicates (MD5 hash) and a high score for visually similar photos (perceptual hash).
- **Photo Selection:** Selects the top 9 photos with the highest "uselessness" score.
- **Deletion Workflow:**
    - **Trier/Re-trier:** Initiates the analysis and displays the 9 candidates.
    - **Supprimer:** Deletes the selected photos from the device gallery.
- **Permissions:** Handles requesting necessary photo gallery access permissions on both iOS and Android.

## 3. Current Plan: UI/UX Polish Pass

This section outlines a comprehensive enhancement of the application's visual design and user experience, adhering to modern, bold, and accessible design principles.

### Theming & Style Overhaul
- **Color Palette:** Transition from a basic `primarySwatch` to a vibrant and harmonious theme generated with `ColorScheme.fromSeed`. A deep purple will be used as the seed color to create a unique and energetic look.
- **Typography:** Integrate the `google_fonts` package.
    - **Headlines:** Use 'Oswald' for a bold, impactful style on titles and key metrics.
    - **Body Text:** Use 'Roboto' for its clarity and readability in buttons and descriptive text.
- **Background:** Apply a subtle noise texture to the main background to add a premium, tactile feel.
- **Component Theming:** Define app-wide styles for `AppBar` and `ElevatedButton` to ensure consistency.

### UI & Visual Enhancements
- **"Lifted" Photo Cards:** Each photo in the grid will be presented in a `Card` with a soft, multi-layered drop shadow to create a sense of depth and make it feel "lifted" off the background.
- **Animated Grid:** Implement a fade-in animation for the photo cards as they appear, providing a smoother and more dynamic user experience.
- **Enhanced Storage Bar:** Redesign the storage indicator to be more visually engaging, with better-defined text and a more prominent progress bar.
- **Iconography:** Add intuitive icons to all action buttons (`Trier`, `Re-trier`, `Supprimer`) to enhance user understanding and navigation.
- **Button Glow Effect:** Style buttons with a subtle "glow" effect using shadows and gradients to make interactive elements more prominent and appealing.

### UX Improvements
- **Engaging Loading State:** Replace the standard `CircularProgressIndicator` with a custom-designed, more visually interesting loading animation and a more descriptive message.
- **Informative Empty State:** Create a more engaging "empty" screen for when no photos are selected, featuring a large icon and clear instructions to guide the user.
- **Haptic Feedback:** (Future consideration) Add subtle haptic feedback for key interactions like button presses and photo deletion.
- **Accessibility:** Ensure all new UI elements and text styles adhere to accessibility standards for contrast and font size.
