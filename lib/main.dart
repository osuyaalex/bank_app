import 'package:banking_app/login%20pages/sign_in_page.dart';
import 'package:banking_app/main_page/home_page.dart';
import 'package:banking_app/main_page/select_track_items.dart';
import 'package:banking_app/providers/text_field_providers.dart';
import 'package:banking_app/root_page.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'firebase_notifications.dart';
import 'firebase_options.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

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

  runApp( MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_){
          return TextFieldProviders();
        })
      ],
  child: const MyApp()));
  _easyLoading();
}
_easyLoading(){
  EasyLoading.instance
    ..indicatorType = EasyLoadingIndicatorType.doubleBounce
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
            path: '/deeplink/summary',
            builder: (_, __) => HomePage()
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

