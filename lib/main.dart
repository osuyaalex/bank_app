import 'package:banking_app/firebase%20network/daily_resets.dart';
import 'package:banking_app/login%20pages/passwordless_signup.dart';
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
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:workmanager/workmanager.dart';
import 'firebase network/sms_service.dart';
import 'firebase_notifications.dart';
import 'firebase_options.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'main_page/summary.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  String currentMonth = DateFormat('MMMM yyyy').format(DateTime.now());
  currentMonth = currentMonth.replaceAll(' ', '');
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    // Your daily spend reset logic
    if (task == "resetDailySpendTask"){
      await DailyResets().resetDailySpend(currentMonth);
     // await DailyResets().clearDailyMessageIds();
    }else if(task == "trackDailySpend"){
      SmsService().getSmsMessages();
    }
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
  Workmanager().initialize(callbackDispatcher,isInDebugMode: false);
  Workmanager().registerPeriodicTask(
    "daily_spend_reset",
    "resetDailySpendTask",
    frequency: const Duration(hours: 24), // Adjust as needed
    initialDelay: Duration(seconds: calculateInitialDelay()),
    //existingWorkPolicy: ExistingWorkPolicy.keep,
  );
  Workmanager().registerPeriodicTask(
    "track_daily_spend",
    "trackDailySpend",
    frequency: const Duration(hours: 2),
    initialDelay: const Duration(minutes: 1),
   // existingWorkPolicy: ExistingWorkPolicy.keep,
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
        GoRoute(
            path: '/deeplink/noPassword',
            builder: (_, __) => const NoPasswordSignIn()
        ),
      ],
      // redirect: (BuildContext context, GoRouterState state) async {
      //   final User? user = FirebaseAuth.instance.currentUser;
      //
      //   // Print the incoming deep link URL
      //   final Uri deepLink = state.uri;
      //   final String path = deepLink.path;
      //   final String? continueUrl = deepLink.queryParameters['continueUrl'];
      //
      //   print("Received deep link path: $path");
      //   print("Continue URL: ${Uri.parse(continueUrl!).path}");
      //
      //   // Check if the deep link path contains '/__/auth/action'
      //
      //     if (user == null) {
      //       // If the user is not signed in, redirect to the login page
      //       return '/deeplink/signIn';
      //     } else {
      //       // If the user is signed in, navigate to the continueUrl
      //       if (continueUrl != null) {
      //         // Use the continueUrl for navigation
      //         // Note: Ensure continueUrl is a valid route in your app
      //         return '/deeplink/signIn'; // Extract path for GoRouter redirection
      //       } else {
      //         // Fallback if continueUrl is null
      //         return '/deeplink/summary';
      //       }
      //     }
      //
      //
      //   // If not a specific deep link or other conditions, navigate to home
      //   return null; // Continue with normal navigation
      // },
    );
    return MaterialApp.router(

      debugShowCheckedModeBanner: false,
      routerConfig: summaryRouter,
      title: 'Flutter Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Color(0xff5AA5E2)),
        useMaterial3: true,
        textTheme: GoogleFonts.notoSansTextTheme(
          Theme.of(context).textTheme,
        ),

      ),
      builder: EasyLoading.init(),
    );
  }
}

