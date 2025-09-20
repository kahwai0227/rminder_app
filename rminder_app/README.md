# RMinder

A modern, privacy-friendly budgeting and savings app built with Flutter.

## Features
- Track expenses and income by category
- Manage savings (sinking funds) and spend for intended purposes
- Edit and confirm deletion of income sources
- Grouped transaction history with icons, notes, and filters
- Home screen widget (Android)
- Works fully offline; your data stays on your device

## App Interface
Here’s what RMinder looks like:  
<table>
  <tr>
	<td align="center">
	  <img src="screenshots/budget_page.png" alt="Budget" width="200"/><br/>
	  <sub><b>Budget page – plan your budget</b></sub>
	</td>
	<td align="center">
	  <img src="screenshots/transaction_page.png" alt="Transaction" width="200"/><br/>
	  <sub><b>Transaction page – track your expenses</b></sub>
	</td>
	<td align="center">
	  <img src="screenshots/savings_page.png" alt="Savings" width="200"/><br/>
	  <sub><b>Savings page – build your savings</b></sub>
	</td>
	<td align="center">
	  <img src="screenshots/report_page.png" alt="Reporting" width="200"/><br/>
	  <sub><b>Report page – monitor your progress</b></sub>
	</td>
	<td align="center">
	  <img src="screenshots/liabilities_page.png" alt="Debt" width="200"/><br/>
	  <sub><b>Liability page – manage your debt</b></sub>
	</td>
  </tr>
</table>

## Getting Started
1. **Clone the repo:**
   ```sh
   git clone https://github.com/kahwai0227/rminder_app.git
   cd rminder_app/rminder_app
   ```
2. **Install dependencies:**
   ```sh
   flutter pub get
   ```
3. **Run the app:**
   ```sh
   flutter run
   ```

## Building for Release
To build a release APK:
```sh
flutter build apk --release
```
The APK will be in `build/app/outputs/flutter-apk/app-release.apk`.

## Contributing
See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License
This project is licensed under the [MIT License](LICENSE).

---

Made with ❤️ by kahwai0227 and contributors.

