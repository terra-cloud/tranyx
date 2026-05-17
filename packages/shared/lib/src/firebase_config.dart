enum AppEnvironment { dev, uat, prod }

class SharedFirebaseOptions {
  final String apiKey;
  final String appId;
  final String messagingSenderId;
  final String projectId;
  final String storageBucket;
  final String? iosClientId;
  final String? iosBundleId;

  const SharedFirebaseOptions({
    required this.apiKey,
    required this.appId,
    required this.messagingSenderId,
    required this.projectId,
    required this.storageBucket,
    this.iosClientId,
    this.iosBundleId,
  });
}

class DefaultFirebaseConfig {
  static const SharedFirebaseOptions devAndroid = SharedFirebaseOptions(
    apiKey: 'AIzaSyBIefcs6_PY3DO6NjDtV5eGOliBt4PBtuA',
    appId: '1:709467070093:android:c5341824036633eddf4cc4',
    messagingSenderId: '709467070093',
    projectId: 'tranyx-dev',
    storageBucket: 'tranyx-dev.firebasestorage.app',
  );

  static const SharedFirebaseOptions devIos = SharedFirebaseOptions(
    apiKey: 'AIzaSyBYMwUbbyKXpWTBpnjhXADQAY9rfvQQEwA',
    appId: '1:709467070093:ios:c9665aafa77e6aacdf4cc4',
    messagingSenderId: '709467070093',
    projectId: 'tranyx-dev',
    storageBucket: 'tranyx-dev.firebasestorage.app',
    iosClientId: '709467070093-shkl2mhs0em1oh92e73pvp0d7o2uu7b4.apps.googleusercontent.com',
    iosBundleId: 'com.terraph.tranyx.dev',
  );

  static const SharedFirebaseOptions uatAndroid = SharedFirebaseOptions(
    apiKey: 'AIzaSyCjYYQhfcbdcJ7S8JrNNDeE6_XRUfTQGxI',
    appId: '1:108125328804:android:53607ae40bd9cec1881d31',
    messagingSenderId: '108125328804',
    projectId: 'tranyx-uat',
    storageBucket: 'tranyx-uat.firebasestorage.app',
  );

  static const SharedFirebaseOptions uatIos = SharedFirebaseOptions(
    apiKey: 'AIzaSyC5KFQw4lWV0ai4n91UmOmPVfHfpnBpFpI',
    appId: '1:108125328804:ios:e4d971551d771ec4881d31',
    messagingSenderId: '108125328804',
    projectId: 'tranyx-uat',
    storageBucket: 'tranyx-uat.firebasestorage.app',
    iosClientId: '108125328804-n9uafcp1mba2cgn8q3cljnsgk3bifibk.apps.googleusercontent.com',
    iosBundleId: 'com.terraph.tranyx.uat',
  );

  static const SharedFirebaseOptions prodAndroid = SharedFirebaseOptions(
    apiKey: 'AIzaSyC_1ifGkKWU1Sw_pm5ySF5aB3eN46UBySE',
    appId: '1:174332525079:android:ef728de52b8560128f7a52',
    messagingSenderId: '174332525079',
    projectId: 'tranyx-app',
    storageBucket: 'tranyx-app.firebasestorage.app',
  );

  static const SharedFirebaseOptions prodIos = SharedFirebaseOptions(
    apiKey: 'AIzaSyCLD9ExfsZmKpSMeXKBF0VupLrBveKexYc',
    appId: '1:174332525079:ios:a389e54587f7f1788f7a52',
    messagingSenderId: '174332525079',
    projectId: 'tranyx-app',
    storageBucket: 'tranyx-app.firebasestorage.app',
    iosClientId: '174332525079-t08i7bqf10ng9ugnrjhgte8h9i8orisn.apps.googleusercontent.com',
    iosBundleId: 'com.terraph.tranyx',
  );
}
