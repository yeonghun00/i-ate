import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:thanks_everyday/core/constants/app_constants.dart';
import 'package:thanks_everyday/core/state/app_state.dart';
import 'package:thanks_everyday/screens/app_wrapper.dart';
import 'package:thanks_everyday/theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ThanksEverydayApp());
}

class ThanksEverydayApp extends StatelessWidget {
  const ThanksEverydayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppState()),
        ChangeNotifierProvider(create: (_) => MealState()),
        ChangeNotifierProvider(create: (_) => SettingsState()),
      ],
      child: MaterialApp(
        title: AppConstants.appTitle,
        theme: AppTheme.appTheme,
        home: const AppWrapper(),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}