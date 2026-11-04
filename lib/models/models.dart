import 'dart:convert';
import 'dart:typed_data';

enum UserRole { admin, employee, customer }

class AppUser {
  String id;
  String fullName;
  String? firstName;
  String? lastName;
  String? suffix;
  String email;
  String phone;
  UserRole role;
  String status; // Active, Disabled
  DateTime dateRegistered;
  String password; // mock only - never do this in production
  String? position; // for employees
  String? employeeId;
  String? profileImage;
  String? otpCode; // mock only - the currently active OTP for this user
  DateTime? otpExpiry;
  bool loyalToggle;
  List<String> hiddenConversations;
  Map<String, DateTime> clearedConversations;

  AppUser({
    required this.id,
    required this.fullName,
    this.firstName,
    this.lastName,
    this.suffix,
    required this.email,
    required this.phone,
    required this.role,
    this.status = 'Active',
    required this.dateRegistered,
    required this.password,
    this.position,
    this.employeeId,
    this.profileImage,
    this.otpCode,
    this.otpExpiry,
    this.loyalToggle = true,
    this.hiddenConversations = const [],
    this.clearedConversations = const {},
  });

  String get roleLabel {
    switch (role) {
      case UserRole.admin:
        return 'Admin';
      case UserRole.employee:
        return 'Employee';
      case UserRole.customer:
        return 'Customer';
    }
  }

  Uint8List? _cachedAvatarBytes;
  String? _lastProfileImageStr;

  Uint8List? get avatarBytes {
    if (profileImage == null || profileImage!.isEmpty) {
      _cachedAvatarBytes = null;
      _lastProfileImageStr = null;
      return null;
    }
    if (_lastProfileImageStr != profileImage) {
      _lastProfileImageStr = profileImage;
      try {
        _cachedAvatarBytes = base64Decode(profileImage!);
      } catch (_) {
        _cachedAvatarBytes = null;
      }
    }
    return _cachedAvatarBytes;
  }
}

class ArchivedRecord {
  final String id;
  final String category; // Users, Employees, Products, Other Records
  final String name;
  final String email;
  final String role;
  final DateTime dateArchived;
  final String archivedBy;
  final AppUser? originalUser;
  final String? originalCustomerId;

  ArchivedRecord({
    required this.id,
    required this.category,
    required this.name,
    required this.email,
    required this.role,
    required this.dateArchived,
    required this.archivedBy,
    this.originalUser,
    this.originalCustomerId,
  });
}

class MenuAddOn {
  final String name;
  final double price;
  final int quantity;
  final String category; // 'Extras' or 'Flavors'
  final bool allowQuantity;
  final List<String> procurementItems;

  MenuAddOn({
    required this.name,
    required this.price,
    this.quantity = 1,
    this.category = 'Extras',
    this.allowQuantity = false,
    List<String>? procurementItems,
  }) : procurementItems = procurementItems ?? [];

  Map<String, dynamic> toMap() => {
        'name': name,
        'price': price,
        'quantity': quantity,
        'category': category,
        'allowQuantity': allowQuantity,
        'procurementItems': procurementItems,
      };

  factory MenuAddOn.fromMap(Map<String, dynamic> map) {
    final procData = map['procurementItems'] as List<dynamic>?;
    return MenuAddOn(
      name: map['name'] as String? ?? '',
      price: (map['price'] as num?)?.toDouble() ?? 0.0,
      quantity: (map['quantity'] as num?)?.toInt().clamp(1, 99).toInt() ?? 1,
      category: map['category'] as String? ?? 'Extras',
      allowQuantity: map['allowQuantity'] as bool? ?? false,
      procurementItems: procData != null ? procData.map((e) => e.toString()).toList() : [],
    );
  }
}

class Product {
  final String id;
  String name;
  String category;
  double price;
  String description;
  String emoji;
  String? imageBase64;
  int stockQuantity;
  List<MenuAddOn> addOns;
  List<String> procurementItems;
  bool isBestSeller;

  /// Hard ceiling for how much stock a single menu item can hold.
  static const int maxStockQuantity = 200;

  /// At or below this quantity (but still > 0) a product is "Low Stock".
  static const int lowStockThreshold = 5;

  Product({
    required this.id,
    required this.name,
    required this.category,
    double? price,
    double? icedPrice,
    double? regularPrice,
    this.description = '',
    this.emoji = '',
    this.imageBase64,
    int stockQuantity = 0,
    List<MenuAddOn>? addOns,
    List<String>? procurementItems,
    this.isBestSeller = false,
  })  : price = price ?? icedPrice ?? regularPrice ?? 0.0,
        stockQuantity = stockQuantity.clamp(0, maxStockQuantity),
        addOns = addOns ?? [],
        procurementItems = procurementItems ?? [];

  bool get isOutOfStock => stockQuantity <= 0;
  bool get isLowStock => !isOutOfStock && stockQuantity <= lowStockThreshold;

  /// "Out of Stock" / "Low Stock" / "In Stock" — matches [StatusBadge]'s
  /// existing color mapping so it renders consistently everywhere.
  String get stockStatus {
    if (isOutOfStock) return 'Out of Stock';
    if (isLowStock) return 'Low Stock';
    return 'In Stock';
  }

  /// Whether this item should currently be orderable from the Kiosk or POS.
  bool get isAvailableForOrder => !isOutOfStock;
}

class InventoryItem {
  final String id;
  String productName;
  int quantity;
  String unit;
  int minimumStock;
  DateTime? expiration;
  String itemType; // 'Inventory Item' or 'Kitchen Item'

  InventoryItem({
    required this.id,
    required this.productName,
    required this.quantity,
    required this.unit,
    required this.minimumStock,
    this.expiration,
    this.itemType = 'Inventory Item',
  });

  String get status {
    if (quantity <= 0) return 'Out of Stock';
    if (expiration != null) {
      final daysLeft = expiration!.difference(DateTime.now()).inDays;
      if (daysLeft < 0) return 'Expired';
      if (daysLeft <= 5) return 'Near Expiration';
    }
    if (quantity <= minimumStock) return 'Low Stock';
    return 'In Stock';
  }
}

class CartItem {
  final Product product;
  int quantity;

  /// Add-ons picked for this specific cart line (e.g. "Extra Shot").
  /// Two cart lines for the same product with different add-on picks are
  /// kept separate rather than merged, since they're priced differently.
  List<MenuAddOn> selectedAddOns;

  CartItem({required this.product, this.quantity = 1, List<MenuAddOn>? selectedAddOns})
      : selectedAddOns = selectedAddOns ?? [];

  /// Per-unit price including add-ons, times quantity.
  double get subtotal {
    final addOnsTotal = selectedAddOns.fold(0.0, (s, a) => s + (a.price * a.quantity));
    return (product.price + addOnsTotal) * quantity;
  }

  /// True if [other] is the same product with the exact same add-ons
  /// selected (order-independent) — used to decide whether tapping a
  /// product again should bump an existing cart line's quantity or start
  /// a new one.
  bool sameSelectionAs(Product p, List<MenuAddOn> addOns) {
    if (product.id != p.id) return false;
    if (selectedAddOns.length != addOns.length) return false;
    final mine = {for (final a in selectedAddOns) a.name: a.quantity};
    final theirs = {for (final a in addOns) a.name: a.quantity};
    return mine.length == theirs.length &&
        mine.entries.every((entry) => theirs[entry.key] == entry.value);
  }
}

class OrderRecord {
  final String id;
  final List<CartItem> items;
  final String source; // Kiosk, POS
  // Pending, Declined, or one of the in-progress Order Status Workflow
  // steps ('Preparing', 'Ready'). There is no persisted 'Completed' value
  // here: once the employee selects "Orders Complete" the order is
  // finalized into a TransactionRecord and removed from this collection.
  final String status;
  final DateTime createdAt;
  final String? customerName;
  double discount;

  /// Firestore user-doc ID of the customer who placed this order (via the
  /// Kiosk). Null for walk-in orders that were never tied to an account.
  /// This — not [customerName] — is the authoritative link used to keep
  /// each customer's order history isolated to their own account.
  final String? customerId;

  /// 'Pay at Counter' or 'GCash'.
  final String paymentMethod;

  /// Auto-generated reference the customer shows the counter staff to
  /// confirm their order. Only set for "Pay at Counter" orders.
  final String? orderNumber;

  /// Base64-encoded image of the customer's GCash payment receipt.
  /// Only set for "GCash" orders.
  final String? proofOfPaymentBase64;

  /// Reason the employee gave for declining a GCash order, surfaced back
  /// to the customer on "My Orders".
  final String? declineReason;

  /// When this order's 20-minute customer countdown lapses. Only set for
  /// customer-placed Kiosk orders (the ones that show the Order ID + timer
  /// modal); null for POS/walk-in orders that have no countdown. Once this
  /// moment passes while the order is still 'Pending', it becomes 'Expired'
  /// and drops out of the employee's Pending Orders in sync with the
  /// customer-side card disappearing.
  final DateTime? expiresAt;

  /// 'Dine In', 'Take Out', or 'Pickup'.
  final String orderType;

  /// Verified total amount entered by employee/admin upon payment approval
  final double? verifiedTotal;
  final double? extractedAmount;
  final String? extractedReferenceId;
  final String? extractedDateTime;
  final double? partialAmountPaid;
  final double? additionalPaymentsPaid;

  /// Receipt generated for this exact order when staff accepted payment
  /// (see [ReceiptRecord]). Null until the Receipt modal has been shown.
  final ReceiptRecord? receipt;

  /// Whether this order was placed by a guest via table QR code.
  final bool isGuest;

  /// Optional table number where the guest is seated.
  final String? tableNumber;

  OrderRecord({
    required this.id,
    required this.items,
    required this.source,
    this.status = 'Pending',
    required this.createdAt,
    this.customerName,
    this.discount = 0,
    this.customerId,
    this.paymentMethod = 'Cash',
    this.orderNumber,
    this.proofOfPaymentBase64,
    this.declineReason,
    this.expiresAt,
    this.orderType = 'Dine In',
    this.verifiedTotal,
    this.extractedAmount,
    this.extractedReferenceId,
    this.extractedDateTime,
    this.partialAmountPaid,
    this.additionalPaymentsPaid,
    this.receipt,
    this.isGuest = false,
    this.tableNumber,
  });

  /// The receipt, but only if it really belongs to this order and this
  /// customer (same order doc ID and same customer ID). A mismatched
  /// receipt is treated as absent, so it can never show on the wrong card.
  ReceiptRecord? get linkedReceipt {
    final r = receipt;
    if (r == null) return null;
    if (r.orderId != id) return null;
    if ((r.customerId ?? '') != (customerId ?? '')) return null;
    return r;
  }

  double get subtotal => items.fold(0, (sum, i) => sum + i.subtotal);
  double get total => verifiedTotal ?? (subtotal - discount).clamp(0, double.infinity);
  double get totalVerifiedPayments => (partialAmountPaid ?? 0) + (additionalPaymentsPaid ?? 0);
  double get remainingBalance => (total - totalVerifiedPayments).clamp(0, double.infinity);
  bool get isFullyPaid => remainingBalance <= 0;
  bool get isPartialPayment => partialAmountPaid != null && partialAmountPaid! > 0 && !isFullyPaid;

  String get displayOrderNumber {
    if (orderNumber != null && orderNumber!.isNotEmpty) {
      return orderNumber!;
    }
    if (id.startsWith('ORD-')) return id;
    final cleanId = id.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toUpperCase();
    final padded = cleanId.padRight(7, '0').substring(0, 7);
    return 'ORD-${padded.substring(0, 4)}-${padded.substring(4)}';
  }
}

/// One printed line on a [ReceiptRecord]: the product, how many, the
/// per-unit price (base price) and any add-ons, plus the line total.
class ReceiptLine {
  final String name;
  final int quantity;
  final double unitPrice;
  final List<MenuAddOn> addOns;
  final double lineTotal;

  ReceiptLine({
    required this.name,
    required this.quantity,
    required this.unitPrice,
    this.addOns = const [],
    required this.lineTotal,
  });

  factory ReceiptLine.fromCartItem(CartItem item) => ReceiptLine(
        name: item.product.name,
        quantity: item.quantity,
        unitPrice: item.product.price,
        addOns: List.of(item.selectedAddOns),
        lineTotal: item.subtotal,
      );

  Map<String, dynamic> toMap() => {
        'name': name,
        'quantity': quantity,
        'unitPrice': unitPrice,
        'addOns': addOns.map((a) => a.toMap()).toList(),
        'lineTotal': lineTotal,
      };

  factory ReceiptLine.fromMap(Map<String, dynamic> map) => ReceiptLine(
        name: map['name'] as String? ?? '',
        quantity: (map['quantity'] as num?)?.toInt() ?? 0,
        unitPrice: (map['unitPrice'] as num?)?.toDouble() ?? 0.0,
        addOns: ((map['addOns'] as List<dynamic>?) ?? const [])
            .whereType<Map>()
            .map((a) => MenuAddOn.fromMap(Map<String, dynamic>.from(a)))
            .toList(),
        lineTotal: (map['lineTotal'] as num?)?.toDouble() ?? 0.0,
      );
}

/// Receipt generated for one specific order when the employee accepts its
/// payment. It is a snapshot of that order's own data (never generic or
/// shared) and is stored on the order document itself ([orderId]), so it
/// stays tied to the right customer and carries over to the sale record
/// when the order is completed.
class ReceiptRecord {
  final String receiptId;
  final String orderId; // Firestore doc id of the order this belongs to
  final String orderNumber; // the customer-facing Order ID
  final String? customerId;
  final String? customerName;
  final String source;
  final String orderType;
  final String paymentMethod;
  final List<ReceiptLine> lines;
  final double subtotal;
  final double discount;
  final double total;

  /// Everything the customer handed over (cash tendered, or GCash + cash).
  final double amountPaid;
  final double? cashTendered;
  final double? gcashAmount;
  final double change;
  final String cashier;
  final DateTime createdAt;
  final String? extractedReferenceId;

  /// True once staff changed anything in the Receipt editor, and when the
  /// finalized receipt was last saved.
  final bool isEdited;
  final DateTime? updatedAt;

  ReceiptRecord({
    required this.receiptId,
    required this.orderId,
    required this.orderNumber,
    this.customerId,
    this.customerName,
    required this.source,
    required this.orderType,
    required this.paymentMethod,
    required this.lines,
    required this.subtotal,
    required this.discount,
    required this.total,
    required this.amountPaid,
    this.cashTendered,
    this.gcashAmount,
    required this.change,
    required this.cashier,
    required this.createdAt,
    this.extractedReferenceId,
    this.isEdited = false,
    this.updatedAt,
  });

  Map<String, dynamic> toMap() => {
        'receiptId': receiptId,
        'orderId': orderId,
        'orderNumber': orderNumber,
        'customerId': customerId,
        'customerName': customerName,
        'source': source,
        'orderType': orderType,
        'paymentMethod': paymentMethod,
        'lines': lines.map((l) => l.toMap()).toList(),
        'subtotal': subtotal,
        'discount': discount,
        'total': total,
        'amountPaid': amountPaid,
        'cashTendered': cashTendered,
        'gcashAmount': gcashAmount,
        'change': change,
        'cashier': cashier,
        'createdAt': createdAt.toIso8601String(),
        'extractedReferenceId': extractedReferenceId,
        'isEdited': isEdited,
        'updatedAt': updatedAt?.toIso8601String(),
      };

  factory ReceiptRecord.fromMap(Map<String, dynamic> map) => ReceiptRecord(
        receiptId: map['receiptId'] as String? ?? '',
        orderId: map['orderId'] as String? ?? '',
        orderNumber: map['orderNumber'] as String? ?? '',
        customerId: map['customerId'] as String?,
        customerName: map['customerName'] as String?,
        source: map['source'] as String? ?? '',
        orderType: map['orderType'] as String? ?? '',
        paymentMethod: map['paymentMethod'] as String? ?? '',
        lines: ((map['lines'] as List<dynamic>?) ?? const [])
            .whereType<Map>()
            .map((l) => ReceiptLine.fromMap(Map<String, dynamic>.from(l)))
            .toList(),
        subtotal: (map['subtotal'] as num?)?.toDouble() ?? 0.0,
        discount: (map['discount'] as num?)?.toDouble() ?? 0.0,
        total: (map['total'] as num?)?.toDouble() ?? 0.0,
        amountPaid: (map['amountPaid'] as num?)?.toDouble() ?? 0.0,
        cashTendered: (map['cashTendered'] as num?)?.toDouble(),
        gcashAmount: (map['gcashAmount'] as num?)?.toDouble(),
        change: (map['change'] as num?)?.toDouble() ?? 0.0,
        cashier: map['cashier'] as String? ?? '',
        createdAt: DateTime.tryParse(map['createdAt'] as String? ?? '') ??
            DateTime.now(),
        extractedReferenceId: map['extractedReferenceId'] as String?,
        isEdited: map['isEdited'] as bool? ?? false,
        updatedAt: DateTime.tryParse(map['updatedAt'] as String? ?? ''),
      );

  /// Builds the receipt from [order] itself — its own customer, Order ID,
  /// line items, quantities, prices and totals — plus the payment figures
  /// the employee just confirmed. Nothing here is generic or shared.
  factory ReceiptRecord.fromOrder(
    OrderRecord order, {
    required double total,
    required double amountPaid,
    double? cashTendered,
    double? gcashAmount,
    required double change,
    required String cashier,
  }) =>
      ReceiptRecord(
        receiptId: 'RCP-${order.displayOrderNumber}',
        orderId: order.id,
        orderNumber: order.displayOrderNumber,
        customerId: order.customerId,
        customerName: order.customerName,
        source: order.source,
        orderType: order.orderType,
        paymentMethod: order.paymentMethod,
        lines: order.items.map(ReceiptLine.fromCartItem).toList(),
        subtotal: order.subtotal,
        discount: order.discount,
        total: total,
        amountPaid: amountPaid,
        cashTendered: cashTendered,
        gcashAmount: gcashAmount,
        change: change,
        cashier: cashier,
        createdAt: DateTime.now(),
        extractedReferenceId: order.extractedReferenceId,
      );
}

class TransactionRecord {
  final String id;
  final List<CartItem> items;
  final double subtotal;
  final double discount;
  final double total;
  final DateTime timestamp;
  final String cashier;

  /// Firestore user-doc ID of the customer this sale belongs to — set when
  /// a kiosk order (placed by a logged-in customer) is accepted. Null for
  /// walk-in POS sales that were never tied to a customer account.
  /// This is what "My Orders" filters on so each customer only ever sees
  /// their own completed orders.
  final String? customerId;
  final String? customerName;

  /// Carried over from the originating Kiosk order (when there was one) so
  /// a customer's full Order History can show how they paid and the
  /// order number they were given — POS walk-in sales leave these null.
  final String? paymentMethod;
  final String? orderNumber;
  final String? orderType;

  /// Receipt carried over from the kiosk order this sale came from.
  final ReceiptRecord? receipt;

  /// Soft-archive flag set when Admin archives this sale, so it disappears
  /// from Admin Order History & Sales Reports, but remains visible to the
  /// customer in their own completed Order History.
  final bool archivedByAdmin;

  /// Whether this order was placed by a guest via table QR code.
  final bool isGuest;

  /// Optional table number where the guest is seated.
  final String? tableNumber;

  TransactionRecord({
    required this.id,
    required this.items,
    required this.subtotal,
    required this.discount,
    required this.total,
    required this.timestamp,
    required this.cashier,
    this.customerId,
    this.customerName,
    this.paymentMethod,
    this.orderNumber,
    this.orderType,
    this.receipt,
    this.archivedByAdmin = false,
    this.isGuest = false,
    this.tableNumber,
  });

  /// Receipt only if it matches this sale's customer and Order ID.
  ReceiptRecord? get linkedReceipt {
    final r = receipt;
    if (r == null) return null;
    if (r.orderNumber != displayOrderNumber) return null;
    if ((r.customerId ?? '') != (customerId ?? '')) return null;
    return r;
  }

  String get displayOrderNumber {
    if (orderNumber != null && orderNumber!.isNotEmpty) {
      return orderNumber!;
    }
    if (id.startsWith('ORD-')) return id;
    final cleanId = id.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toUpperCase();
    final padded = cleanId.padRight(7, '0').substring(0, 7);
    return 'ORD-${padded.substring(0, 4)}-${padded.substring(4)}';
  }
}

class PayrollRecord {
  final String id;
  final String employeeId;
  final String employeeName;
  final String position;
  final double netSalary;
  final String status;
  final DateTime date;

  PayrollRecord({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    required this.position,
    required this.netSalary,
    required this.status,
    required this.date,
  });
}

class Employee {
  final String id;
  String name;
  String position;
  double dailyRate;
  double daysWorked;
  double bonus;
  double deductions;
  String status; // Paid, Pending

  /// When this employee's payroll was last marked Paid (and daysWorked,
  /// bonus and deductions were reset to 0 for a fresh cycle). Null if
  /// they've never been paid yet, in which case the whole attendance
  /// history counts toward the current cycle.
  DateTime? lastPaidAt;

  Employee({
    required this.id,
    required this.name,
    required this.position,
    required this.dailyRate,
    this.daysWorked = 0,
    this.bonus = 0,
    this.deductions = 0,
    this.status = 'Pending',
    this.lastPaidAt,
  });

  double get basicSalary => dailyRate * daysWorked;
  double get netSalary => basicSalary + bonus - deductions;
}

class AttendanceRecord {
  String id; // Firestore doc id, needed to update this record with a time-out
  final String employeeName;
  final DateTime date;
  final DateTime? createdAt;
  final String timeIn;
  String? timeOut;
  final String status;
  final String method; // RFID, QR

  AttendanceRecord({
    this.id = '',
    required this.employeeName,
    required this.date,
    this.createdAt,
    required this.timeIn,
    this.timeOut,
    this.status = 'Present',
    this.method = 'RFID',
  });

  bool get hasTimedOut => timeOut != null && timeOut!.isNotEmpty;

  bool isSameDay(DateTime other) =>
      date.year == other.year && date.month == other.month && date.day == other.day;
}

class FeedbackRecord {
  final String id;
  final String customerName;
  final int rating;
  final String comment;
  final String category;
  final DateTime date;
  String status; // New, Reviewed
  String? reply;

  /// Firestore user-doc ID of the customer who left this feedback, and the
  /// completed order (transaction ID) it was left for. Together these tie
  /// the feedback to exactly one customer's exactly one completed order —
  /// used to (a) limit each order to a single feedback submission and
  /// (b) surface the feedback back on that specific order in "My Orders".
  final String? customerId;
  final String? orderId;

  FeedbackRecord({
    required this.id,
    required this.customerName,
    required this.rating,
    required this.comment,
    required this.category,
    required this.date,
    this.status = 'New',
    this.reply,
    this.customerId,
    this.orderId,
  });
}

class ChatMessage {
  final String id; // Firestore doc id, needed to target this message for deletion
  final String sender;
  final String text;
  final String? imageUrl;
  final String? fileName;
  final String? fileData;
  final DateTime timestamp;
  bool read;
  final List<String> deletedFor; // names this message is hidden from ("Delete for You")
  ChatMessage(
      {this.id = '',
      required this.sender,
      required this.text,
      this.imageUrl,
      this.fileName,
      this.fileData,
      required this.timestamp,
      this.read = false,
      this.deletedFor = const []});
}

class Conversation {
  final String withName;
  final List<ChatMessage> messages;
  final bool isGroup;
  final String id;
  final List<String> members;
  final String? groupImageBase64;

  Conversation({
    required this.withName,
    required this.messages,
    this.isGroup = false,
    this.id = '',
    this.members = const [],
    this.groupImageBase64,
  });
}

class PettyCashEntry {
  final String id;
  final String description;
  final String category;
  final double amount; // positive = cash added, negative = expense
  final DateTime date;
  PettyCashEntry({
    this.id = '',
    required this.description,
    required this.category,
    required this.amount,
    required this.date,
  });
}

class ProcurementRecord {
  final String id;
  final String productName;
  final String supplier;
  int quantity;
  final double cost;
  final DateTime date;
  final String status; // Requested, Restocked
  final String itemType; // 'Inventory Item' or 'Kitchen Item'
  final DateTime? expiration;
  ProcurementRecord({
    required this.id,
    required this.productName,
    required this.supplier,
    required this.quantity,
    required this.cost,
    required this.date,
    this.status = 'Restocked',
    this.itemType = 'Inventory Item',
    this.expiration,
  });
}

class PromotionRecord {
  final String productName;
  final String promoType; // Buy 1 Take 1, 10% Discount, etc.
  final DateTime createdAt;
  PromotionRecord(
      {required this.productName,
      required this.promoType,
      required this.createdAt});
}

class AppNotification {
  final String title;
  final String body;
  final String type; // Inventory, Expiration, POS, Feedback, Payroll
  final DateTime time;
  bool read;
  AppNotification({
    required this.title,
    required this.body,
    required this.type,
    required this.time,
    this.read = false,
  });
}
