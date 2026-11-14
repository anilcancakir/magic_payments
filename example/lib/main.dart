import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';
import 'package:magic_payments/magic_payments.dart';

const Color _ink = Color(0xFF111827);
const Color _accent = Color(0xFF4F46E5);
const TextStyle _text = TextStyle(color: _ink, fontSize: 16);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Magic.init(
    configs: [
      {
        'network': {
          'drivers': {
            'api': {
              // The backend that serves the /billing endpoints.
              'base_url': 'http://127.0.0.1:8000/api/v1',
            },
          },
        },
        'payments': {
          // `platform` is the only mode the package serves: the build decides
          // which driver answers.
          'driver': 'platform',
        },
        'app': {
          'providers': [
            (app) => NetworkServiceProvider(app),
            (app) => PaymentsServiceProvider(app),
          ],
        },
      },
    ],
  );

  runApp(const ExampleApp());
}

/// One page: the resolved rails, and a button that reads the entitlement.
class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return WidgetsApp(
      title: 'magic_payments example',
      color: _accent,
      textStyle: _text,
      pageRouteBuilder: <T>(RouteSettings settings, WidgetBuilder builder) {
        return PageRouteBuilder<T>(
          settings: settings,
          pageBuilder: (context, _, _) => builder(context),
        );
      },
      home: const BillingPage(),
    );
  }
}

class BillingPage extends StatefulWidget {
  const BillingPage({super.key});

  @override
  State<BillingPage> createState() => _BillingPageState();
}

class _BillingPageState extends State<BillingPage> {
  String _result = 'Not read yet.';

  Future<void> _readEntitlement() async {
    setState(() => _result = 'Reading...');

    try {
      final BillingEntitlement entitlement =
          await Payments.currentEntitlement();
      setState(() {
        _result =
            'plan: ${entitlement.plan}, status: ${entitlement.planStatus.name}, '
            'manage via: ${entitlement.manageVia.name}';
      });
    } on BillingException catch (error) {
      setState(() => _result = '${error.code.name}: ${error.message}');
    }
  }

  @override
  Widget build(BuildContext context) {
    // A rail is checked, never assumed: null is a build that cannot serve it.
    final bool hasWeb = Payments.web != null;
    final bool hasStore = Payments.store != null;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('driver: ${Payments.billing.runtimeType}', style: _text),
            Text(
              'payments.driver: ${Config.get<String>('payments.driver')}',
              style: _text,
            ),
            Text('web rail: ${hasWeb ? 'present' : 'absent'}', style: _text),
            Text(
              'store rail: ${hasStore ? 'present' : 'absent'}',
              style: _text,
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: _readEntitlement,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                color: _accent,
                child: const Text(
                  'Read entitlement',
                  style: TextStyle(color: Color(0xFFFFFFFF)),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(_result, style: _text),
          ],
        ),
      ),
    );
  }
}
