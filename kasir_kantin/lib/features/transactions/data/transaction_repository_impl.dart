import '../domain/checkout_line.dart';
import '../domain/local_transaction.dart';
import '../domain/payment_method.dart';
import '../domain/transaction_repository.dart';
import 'transaction_local_data_source.dart';

class TransactionRepositoryImpl implements TransactionRepository {
  TransactionRepositoryImpl({required this._local});

  final TransactionLocalDataSource _local;

  @override
  Future<LocalTransaction> createLocalTransaction({
    required List<CheckoutLine> lines,
    required PaymentMethod paymentMethod,
  }) {
    return _local.create(lines: lines, paymentMethod: paymentMethod);
  }
}
