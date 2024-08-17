import 'package:banking_app/firebase%20network/daily_resets.dart';
import 'package:banking_app/login%20pages/sign_in_page.dart';
import 'package:banking_app/main_page/home_page.dart';
import 'package:banking_app/main_page/select_track_items.dart';
import 'package:banking_app/providers/progressba_provider.dart';
import 'package:banking_app/root_page.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:workmanager/workmanager.dart';
import 'firebase_notifications.dart';
import 'firebase_options.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'main_page/summary.dart';


void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    // Your daily spend reset logic
    await DailyResets().resetDailySpend();
    await DailyResets().clearDailyMessageIds();
    return Future.value(true);
  });
}
void main() async{
  tz.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation('Africa/Lagos'));
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await FirebaseAppCheck.instance.activate(
    webProvider: ReCaptchaV3Provider('recaptcha-v3-site-key'),
    androidProvider: AndroidProvider.debug,
    appleProvider: AppleProvider.appAttest,
  );
  await FirebaseApi().initNotifications();
  Workmanager().initialize(callbackDispatcher, isInDebugMode: true);
  Workmanager().registerPeriodicTask(
    "1",
    "resetDailySpendTask",
    frequency: const Duration(hours: 24), // Adjust as needed
    initialDelay: Duration(seconds: calculateInitialDelay()),
  );

  runApp( MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_){
          return ProgressBarProvider();
        })
      ],
  child: const MyApp()));
  _easyLoading();
}
int calculateInitialDelay() {
  final now = DateTime.now();
  final nextMidnight = DateTime(now.year, now.month, now.day + 1);
  final difference = nextMidnight.difference(now);
  return difference.inSeconds - 60; // Schedule to run at 11:59 PM local time
}
_easyLoading(){
  EasyLoading.instance
    ..indicatorType = EasyLoadingIndicatorType.wave
    ..loadingStyle = EasyLoadingStyle.custom
    ..indicatorSize = 30.0
    ..radius = 50.0
    ..progressColor = const Color(0xff5AA5E2)
    ..backgroundColor = Colors.transparent
    ..textColor = Colors.cyan
    ..indicatorColor =  Color(0xff5AA5E2)
    ..userInteractions = true
    ..boxShadow = <BoxShadow>[]
    ..dismissOnTap = false;

}
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(statusBarColor: Colors.transparent));
    final summaryRouter = GoRouter(
      initialLocation:'/root' ,
      routes: [
        GoRoute(
            path: '/root',
            builder: (_, __) => RootPage()
        ),
        GoRoute(
            path: '/deeplink/signIn',
            builder: (_, __) => const SignInPage()
        ),
        GoRoute(
            path: '/deeplink/home',
            builder: (_, __) => HomePage()
        ),
        GoRoute(
            path: '/deeplink/summary',
            builder: (_, __) => const Summary()
        ),
        GoRoute(
            path: '/deeplink/selectTrack',
            builder: (_, __) => const SelectTrackItems()
        ),
      ],
    );
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      routerConfig: summaryRouter,
      title: 'Flutter Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Color(0xff5AA5E2)),
        useMaterial3: true,
        textTheme: GoogleFonts.dmSansTextTheme(
          Theme.of(context).textTheme,
        ),

      ),
      builder: EasyLoading.init(),
    );
  }
}

