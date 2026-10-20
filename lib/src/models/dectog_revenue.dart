/// The store a purchase was made in. Sent as `store`.
enum DectogStore {
  appStore('app_store'),
  play('play');

  const DectogStore(this.wire);

  /// The value on the wire.
  final String wire;
}

/// What was bought. Sent as `purchase_type`.
enum DectogPurchaseType {
  oneTime('one_time'),
  subscription('subscription');

  const DectogPurchaseType(this.wire);

  /// The value on the wire.
  final String wire;
}

/// What happened to the transaction. Sent as `transaction_type`.
///
/// A [refund] subtracts its revenue from the link's net revenue; a [cancel]
/// (a subscription that will not renew) counts nothing.
enum DectogTransactionType {
  purchase('purchase'),
  refund('refund'),
  cancel('cancel');

  const DectogTransactionType(this.wire);

  /// The value on the wire.
  final String wire;
}
