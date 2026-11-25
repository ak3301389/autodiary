import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';

import 'firebase_options.dart';
import 'core/theme.dart';
import 'models/expense.dart'; // <-- ЭТА СТРОКА ИСПРАВЛЯЕТ ОШИБКУ С Expense
import 'providers/auth_provider.dart';
import 'providers/data_provider.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/add_car_screen.dart';
import 'screens/car_screen.dart';
import 'screens/add_expense_screen.dart';
import 'screens/stats_screen.dart';
import 'screens/fuel_price_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const AutoDiaryApp());
}

class AutoDiaryApp extends StatelessWidget {
  const AutoDiaryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AuthProvider(),
      child: Consumer<AuthProvider>(
        builder: (context, auth, _) {
          final router = GoRouter(
            initialLocation: '/',
            redirect: (context, state) {
              final loggedIn = auth.isSignedIn;
              final loggingIn = state.matchedLocation == '/login';
              if (!loggedIn && !loggingIn) return '/login';
              if (loggedIn && loggingIn) return '/';
              return null;
            },
            routes: [
              GoRoute(
                path: '/login',
                builder: (context, state) => const LoginScreen(),
              ),
              GoRoute(
                path: '/',
                builder: (context, state) => const HomeScreen(),
              ),
              GoRoute(
                path: '/car/add',
                builder: (context, state) => const AddCarScreen(),
              ),
              GoRoute(
                path: '/car/:id',
                builder: (context, state) =>
                    CarScreen(carId: state.pathParameters['id']!),
              ),
              GoRoute(
                path: '/expense/add/:carId',
                builder: (context, state) {
                  final expenseToEdit = state.extra as Expense?;
                  return AddExpenseScreen(
                    carId: state.pathParameters['carId']!,
                    expenseToEdit: expenseToEdit,
                  );
                },
              ),
              GoRoute(
                path: '/stats',
                builder: (context, state) => const StatsScreen(),
              ),
              GoRoute(
                path: '/fuel-prices',
                builder: (context, state) => const FuelPriceScreen(),
              ),
            ],
          );

          Widget child = MaterialApp.router(
            title: 'АвтоДневник',
            theme: AppTheme.light(),
            routerConfig: router,
            debugShowCheckedModeBanner: false,
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [Locale('ru', 'RU')],
            locale: const Locale('ru', 'RU'),
          );

          if (auth.isSignedIn) {
            child = ChangeNotifierProvider(
              create: (_) => DataProvider(auth.user!.uid),
              child: child,
            );
          }
          return child;
        },
      ),
    );
  }
}
