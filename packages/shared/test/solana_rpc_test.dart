import 'package:test/test.dart';
import 'package:shared/shared.dart';

void main() {
  group('Solana RPC URL and Environment Tests', () {
    test('Env.solanaRpcUrl returns configured value or empty default', () {
      final rpc = Env.solanaRpcUrl;
      expect(rpc, isA<String>());
    });

    test('Env.get fallback for SOLANA_RPC_URL', () {
      final fallbackRpc = Env.get('SOLANA_RPC_URL', defaultValue: 'https://api.mainnet-beta.solana.com');
      expect(fallbackRpc, isNotEmpty);
      expect(fallbackRpc.startsWith('http'), isTrue);
    });
  });
}
