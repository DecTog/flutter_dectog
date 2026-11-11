/// The store a purchase was made in. Sent as `store`.
enum AdtoStore {
  appStore('app_store'),
  play('play');

  const AdtoStore(this.wire);

  /// The value on the wire.
  final String wire;
}

/// What was bought. Sent as `purchase_type`.
enum AdtoPurchaseType {
  oneTime('one_time'),
  subscription('subscription');

  const AdtoPurchaseType(this.wire);

  /// The value on the wire.
  final String wire;
}

/// What happened to the transaction. Sent as `transaction_type`.
///
/// A [refund] subtracts its revenue from the link's net revenue; a [cancel]
/// (a subscription that will not renew) counts nothing.
enum AdtoTransactionType {
  purchase('purchase'),
  refund('refund'),
  cancel('cancel');

  const AdtoTransactionType(this.wire);

  /// The value on the wire.
  final String wire;
}
