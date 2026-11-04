import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image/image.dart' as img;
import '../models/models.dart';
import 'email_service.dart';
import 'notification_service.dart';
import '../config/payment_config.dart';

class RegistrationValidationException implements Exception {
  final String message;
  const RegistrationValidationException(this.message);

  @override
  String toString() => message;
}

/// Central backend using Firebase Firestore.
/// A ChangeNotifier singleton so any screen can read/mutate shared data
/// and rebuild automatically.
class AppData extends ChangeNotifier {
  AppData._internal() {
    _initializeFromFirestore();
  }
  static final AppData instance = AppData._internal();

  // ---------------- Session ----------------
  AppUser? currentUser;
  bool _messagesListenerSet = false;
  bool _productsListenerSet = false;
  bool _notificationsListenerSet = false;
  bool _inventoryListenerSet = false;
  bool _transactionsListenerSet = false;
  bool _kioskOrdersListenerSet = false;
  bool _kioskOrdersInitialLoad = true;
  bool _storeConfigListenerSet = false;
  bool _pettyCashListenerSet = false;  bool _payrollHistoryListenerSet = false;
  bool _procurementListenerSet = false;
  bool _attendanceListenerSet = false;
  bool _employeesListenerSet = false;
  bool _usersListenerSet = false;
  bool _pendingUsersListenerSet = false;
  final Map<String, AppUser> _activeUsersMap = {};
  final Map<String, AppUser> _pendingUsersMap = {};

  void _rebuildUsersList() {
    users.clear();
    users.addAll(_activeUsersMap.values);
    users.addAll(_pendingUsersMap.values);
    if (currentUser != null && _activeUsersMap.containsKey(currentUser!.id)) {
      currentUser = _activeUsersMap[currentUser!.id];
    }
    notifyListeners();
  }
  bool _archiveListenerSet = false;
  bool _feedbacksListenerSet = false;

  /// Periodic safety-net that expires customer Kiosk orders whose 20-minute
  /// countdown has lapsed but whose customer never reported it (e.g. the app
  /// was closed before the timer fired). Started once by [_loadKioskOrders].
  Timer? _expirySweep;

  /// Periodic safety-net that auto-closes attendance shifts left open past
  /// the cafe's 2:30 AM cutoff (e.g. an employee forgot to scan out, or
  /// left without scanning). Started once by [_loadAttendance].
  Timer? _attendanceSweep;

  // ---------------- Collections ----------------
  String gcashAccountName = 'Overnight Cafe';
  String gcashAccountNumber = '0917 123 4567';
  String? gcashQrBase64;
  String receiptTitle = 'OVERNIGHT CAFE';
  String receiptSubtitle = 'Brgy. Calumpang, Liliw, Laguna';
  String receiptFooter = 'Thank you for your order!';
  String selectedPrinterName = '';
  String selectedPrinterAddress = '';
  bool isPrinterConnected = false;
  String paperSize = '80mm';
  bool autoPrintReceipt = true;
  int printCopies = 1;

  final List<AppUser> users = [];
  final List<ArchivedRecord> archive = [];
  final List<Product> products = [];
  final List<InventoryItem> inventory = [];
  final List<OrderRecord> kioskOrders = [];
  final List<TransactionRecord> transactions = [];
  final List<Employee> employees = [];
  final List<PayrollRecord> payrollHistory = [];
  final List<AttendanceRecord> attendance = [];
  final List<FeedbackRecord> feedbacks = [];
  final List<Conversation> adminEmployeeChats = [];
  final Map<String, List<String>> roleHiddenConversations = {};
  final List<PettyCashEntry> pettyCash = [];
  final List<ProcurementRecord> procurement = [];
  final List<PromotionRecord> promotions = [];
  final List<AppNotification> notifications = [];
  List<CartItem> posCart = [];
  String posCustomerName = '';

  void updatePosCart(List<CartItem> newCart) {
    posCart = List.from(newCart);
    notifyListeners();
  }

  void updatePosCustomerName(String name) {
    posCustomerName = name;
    notifyListeners();
  }

  void clearPosCart() {
    posCart.clear();
    posCustomerName = '';
    notifyListeners();
  }

  int get unreadNotifications => notifications.where((n) => !n.read).length;

  int get unreadMessagesCount {
    final user = currentUser;
    if (user == null) return 0;
    final adminName = user.fullName.isNotEmpty ? user.fullName : 'Admin';
    final selfRole = user.role == UserRole.admin ? adminName : user.fullName;
    int count = 0;
    for (final convo in adminEmployeeChats) {
      if (convo.isGroup) {
        if (user.role == UserRole.admin || convo.members.contains(user.fullName)) {
          for (final m in convo.messages) {
            if (!m.read && m.sender != selfRole && m.sender != 'Admin' && !m.deletedFor.contains(selfRole) && !m.deletedFor.contains('Admin')) {
              count++;
            }
          }
        }
      } else {
        if (user.role == UserRole.admin) {
          if (convo.id.startsWith('p2p_Admin_') || convo.id.contains('_Admin_') || convo.withName == 'Admin' || convo.withName == adminName) {
            for (final m in convo.messages) {
              if (!m.read && m.sender != selfRole && m.sender != 'Admin' && !m.deletedFor.contains(selfRole) && !m.deletedFor.contains('Admin')) {
                count++;
              }
            }
          }
        } else {
          final isAdminChat = convo.id == 'p2p_Admin_${user.fullName}' || convo.id.contains('_${user.fullName}') || convo.withName == user.fullName || convo.withName == adminName;
          final isP2PChat = convo.id.startsWith('p2p_') && !convo.id.startsWith('p2p_Admin_') && (convo.id.contains('_${user.fullName}') || convo.id.startsWith('p2p_${user.fullName}_'));
          if (isAdminChat || isP2PChat) {
            for (final m in convo.messages) {
              if (!m.read && m.sender != user.fullName && !m.deletedFor.contains(user.fullName)) {
                count++;
              }
            }
          }
        }
      }
    }
    return count;
  }

  // Menu item stock (separate from raw-ingredient inventory above).
  List<Product> get lowStockProducts =>
      products.where((p) => p.isLowStock).toList();
  List<Product> get outOfStockProducts =>
      products.where((p) => p.isOutOfStock).toList();
  List<Product> get orderableProducts =>
      products.where((p) => p.isAvailableForOrder).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  /// Completed-sale ranking used by the customer Menu. Pending kiosk/POS
  /// orders are intentionally excluded because they are not actual sales yet.
  /// Only products explicitly checked/marked as Best Seller by the Admin.
  List<Product> get bestSellingProducts {
    return orderableProducts.where((p) => p.isBestSeller).toList();
  }

  // Helper methods for getting users by role (useful for messaging module)
  List<AppUser> get employeeUsers =>
      users.where((u) => u.role == UserRole.employee).toList();
  List<AppUser> get adminUsers =>
      users.where((u) => u.role == UserRole.admin).toList();
  List<AppUser> get customerUsers =>
      users.where((u) => u.role == UserRole.customer).toList();

  int getCompletedOrdersCount(String customerId) {
    return transactions.where((t) => t.customerId == customerId).length;
  }

  bool isCustomerLoyal(AppUser user) {
    if (user.role != UserRole.customer) return false;
    return getCompletedOrdersCount(user.id) >= 5 && user.loyalToggle;
  }

  bool isCustomerLoyalById(String? customerId) {
    if (customerId == null || customerId.isEmpty) return false;
    if (_activeUsersMap.containsKey(customerId)) {
      final user = _activeUsersMap[customerId]!;
      return isCustomerLoyal(user);
    }
    final matches = users.where((u) => u.id == customerId);
    if (matches.isNotEmpty) {
      return isCustomerLoyal(matches.first);
    }
    return false;
  }

  bool isCustomerLoyalByName(String? customerName) {
    if (customerName == null || customerName.isEmpty) return false;
    final matches = customerUsers.where((u) => u.fullName.toLowerCase() == customerName.toLowerCase());
    if (matches.isEmpty) return false;
    return isCustomerLoyal(matches.first);
  }

  List<AppUser> get loyalCustomers {
    return customerUsers.where((u) => getCompletedOrdersCount(u.id) >= 5).toList();
  }

  Future<void> updateCustomerLoyalToggle(String userId, bool value) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(userId).update({
        'loyalToggle': value,
      });
      if (_activeUsersMap.containsKey(userId)) {
        _activeUsersMap[userId]!.loyalToggle = value;
      }
      final idx = users.indexWhere((u) => u.id == userId);
      if (idx != -1) {
        users[idx].loyalToggle = value;
      }
      if (currentUser != null && currentUser!.id == userId) {
        currentUser!.loyalToggle = value;
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Error updating customer loyal toggle: $e');
    }
  }

  Future<void> _initializeFromFirestore() async {
    try {
      // Clear all lists first
      users.clear();
      products.clear();
      inventory.clear();
      employees.clear();
      attendance.clear();
      feedbacks.clear();
      // Load from Firestore collections - continue even if one fails
      // We DO NOT clear adminEmployeeChats here to avoid breaking the listener references,
      // it handles its own deduplication and mapping.
      adminEmployeeChats.removeWhere((c) => c.isGroup); // Clear groups to let them reload cleanly without duplicates
      pettyCash.clear();
      procurement.clear();
      promotions.clear();
      notifications.clear();
      archive.clear();
      kioskOrders.clear();
      transactions.clear();

      // Load from Firestore collections - continue even if one fails
      await _loadUsers()
          .catchError((e) => debugPrint('Error loading users: $e'));
      await _loadProducts()
          .catchError((e) => debugPrint('Error loading products: $e'));
      await _loadInventory()
          .catchError((e) => debugPrint('Error loading inventory: $e'));
      await _loadEmployees()
          .catchError((e) => debugPrint('Error loading employees: $e'));
      await _loadPayrollHistory()
          .catchError((e) => debugPrint('Error loading payrollHistory: $e'));
      await _loadAttendance()
          .catchError((e) => debugPrint('Error loading attendance: $e'));
      await _loadFeedbacks()
          .catchError((e) => debugPrint('Error loading feedbacks: $e'));
      await _loadAdminEmployeeChats().catchError(
          (e) => debugPrint('Error loading adminEmployeeChats: $e'));
      await _loadPettyCash()
          .catchError((e) => debugPrint('Error loading pettyCash: $e'));
      await _loadProcurement()
          .catchError((e) => debugPrint('Error loading procurement: $e'));
      await _loadPromotions()
          .catchError((e) => debugPrint('Error loading promotions: $e'));
      await _loadNotifications()
          .catchError((e) => debugPrint('Error loading notifications: $e'));
      await _loadArchive()
          .catchError((e) => debugPrint('Error loading archive: $e'));
      await _loadKioskOrders()
          .catchError((e) => debugPrint('Error loading kioskOrders: $e'));
      await _loadTransactions()
          .catchError((e) => debugPrint('Error loading transactions: $e'));
      await _loadGlobalAddOns()
          .catchError((e) => debugPrint('Error loading globalAddOns: $e'));
      await _loadStoreConfig()
          .catchError((e) => debugPrint('Error loading storeConfig: $e'));

      notifyListeners();
    } catch (e) {
      debugPrint('Error in _initializeFromFirestore: $e');
      // Still notify listeners so UI knows to show empty state or error
      notifyListeners();
    }
  }

  // ===================== LOADERS =====================
  Future<void> _loadUsers() async {
    if (!_usersListenerSet) {
      _usersListenerSet = true;
      FirebaseFirestore.instance.collection('users').snapshots().listen((snapshot) {
        _activeUsersMap.clear();
        for (final doc in snapshot.docs) {
          try {
            final data = doc.data();
            final fn = data['firstName'] as String? ?? '';
            final ln = data['lastName'] as String? ?? '';
            final suf = data['suffix'] as String?;
            final full = data['fullName'] as String? ?? (suf != null && suf.isNotEmpty ? '$fn $ln $suf'.trim() : '$fn $ln'.trim());
            _activeUsersMap[doc.id] = AppUser(
              id: doc.id,
              fullName: full.isNotEmpty ? full : 'User',
              firstName: fn,
              lastName: ln,
              suffix: suf,
              email: data['email'] as String? ?? '',
              phone: data['phone'] as String? ?? '',
              role: _parseUserRole(data['role'] as String? ?? 'customer'),
              status: data['status'] as String? ?? 'Active',
              dateRegistered: (data['dateRegistered'] as Timestamp?)?.toDate() ??
                  DateTime.now(),
              password: data['password'] as String? ?? '',
              position: data['position'] as String?,
              employeeId: data['employeeId'] as String?,
              profileImage: data['profileImage'] as String?,
              otpCode: data['otpCode'] as String?,
              otpExpiry: (data['otpExpiry'] as Timestamp?)?.toDate(),
              loyalToggle: data['loyalToggle'] is bool
                  ? data['loyalToggle'] as bool
                  : (data['loyalToggle'] != null
                      ? data['loyalToggle'].toString().toLowerCase() == 'true' ||
                          data['loyalToggle'] == 1
                      : true),
              hiddenConversations: List<String>.from(data['hiddenConversations'] as List? ?? const []),
              clearedConversations: (() {
                final rawCleared = data['clearedConversations'] as Map? ?? {};
                final Map<String, DateTime> parsed = {};
                rawCleared.forEach((k, v) {
                  if (v is Timestamp) {
                    parsed[k.toString()] = v.toDate();
                  } else if (v is String) {
                    final dt = DateTime.tryParse(v);
                    if (dt != null) parsed[k.toString()] = dt;
                  }
                });
                return parsed;
              })(),
            );
          } catch (e) {
            debugPrint('Error loading user doc ${doc.id}: $e');
          }
        }
        _rebuildUsersList();
      });
    }

    if (!_pendingUsersListenerSet) {
      _pendingUsersListenerSet = true;
      FirebaseFirestore.instance.collection('pendingRegistrations').snapshots().listen((snapshot) {
        _pendingUsersMap.clear();
        for (final doc in snapshot.docs) {
          try {
            final data = doc.data();
            final fn = data['firstName'] as String? ?? '';
            final ln = data['lastName'] as String? ?? '';
            final full = data['fullName'] as String? ?? '$fn $ln'.trim();
            _pendingUsersMap[doc.id] = AppUser(
              id: doc.id,
              fullName: full.isNotEmpty ? full : 'User',
              firstName: fn,
              lastName: ln,
              email: data['email'] as String? ?? '',
              phone: data['phone'] as String? ?? '',
              role: _parseUserRole(data['role'] as String? ?? 'customer'),
              status: 'Pending Verification',
              dateRegistered: (data['dateRegistered'] as Timestamp?)?.toDate() ??
                  DateTime.now(),
              password: data['password'] as String? ?? '',
            );
          } catch (e) {
            debugPrint('Error loading pending user doc ${doc.id}: $e');
          }
        }
        _rebuildUsersList();
      });
    }
  }

  Future<void> _loadProducts() async {
    if (!_productsListenerSet) {
      _productsListenerSet = true;
      FirebaseFirestore.instance.collection('products').snapshots().listen((snapshot) {
        products.clear();
        for (final doc in snapshot.docs) {
          try {
            final data = doc.data();
            final p = (data['price'] as num?)?.toDouble() ??
                (data['icedPrice'] as num?)?.toDouble() ??
                (data['regularPrice'] as num?)?.toDouble() ??
                0.0;
            final addOnsData = data['addOns'] as List<dynamic>?;
            final List<MenuAddOn> addOns = [];
            if (addOnsData != null) {
              for (final a in addOnsData) {
                if (a is Map<String, dynamic>) {
                  addOns.add(MenuAddOn.fromMap(a));
                }
              }
            }

            final procData = data['procurementItems'] as List<dynamic>?;
            final List<String> procurementItems = procData != null
                ? procData.map((e) => e.toString()).toList()
                : [];

            products.add(Product(
              id: doc.id,
              name: data['name'] as String? ?? 'Unknown Product',
              category: data['category'] as String? ?? 'Unknown',
              price: p,
              description: data['description'] as String? ?? '',
              emoji: data['emoji'] as String? ?? '',
              imageBase64: data['imageBase64'] as String? ?? data['image'] as String?,
              stockQuantity: (data['stockQuantity'] as num?)?.toInt() ?? 0,
              addOns: addOns,
              procurementItems: procurementItems,
              isBestSeller: data['isBestSeller'] as bool? ?? false,
            ));
          } catch (e) {
            debugPrint('Error loading product doc ${doc.id}: $e');
          }
        }
        products.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        notifyListeners();
      });
    }
  }

  Future<void> _loadInventory() async {
    if (!_inventoryListenerSet) {
      _inventoryListenerSet = true;
      FirebaseFirestore.instance.collection('inventory').snapshots().listen((snapshot) {
        inventory.clear();
        for (final doc in snapshot.docs) {
          try {
            final data = doc.data();
            inventory.add(InventoryItem(
              id: doc.id,
              productName: data['productName'] as String? ?? '',
              quantity: (data['quantity'] as int?) ?? 0,
              unit: data['unit'] as String? ?? '',
              minimumStock: (data['minimumStock'] as int?) ?? 0,
              expiration: (data['expiration'] as Timestamp?)?.toDate(),
              itemType: data['itemType'] as String? ?? (data['expiration'] != null ? 'Kitchen Item' : 'Inventory Item'),
            ));
          } catch (e) {
            debugPrint('Error loading inventory doc ${doc.id}: $e');
          }
        }
        notifyListeners();
      });
    }
  }

  Future<void> _loadEmployees() async {
    if (!_employeesListenerSet) {
      _employeesListenerSet = true;
      FirebaseFirestore.instance.collection('employees').snapshots().listen((snapshot) async {
        employees.clear();
        final existingEmployeeNames = <String>{};
        for (final doc in snapshot.docs) {
          try {
            final data = doc.data();
            final name = data['name'] as String? ?? '';
            existingEmployeeNames.add(name);
            final dailyRate = (data['dailyRate'] as num?)?.toDouble() ??
                ((data['hourlyRate'] as num?)?.toDouble() != null
                    ? (data['hourlyRate'] as num).toDouble() * 8
                    : 300.0);
            final daysWorked = (data['daysWorked'] as num?)?.toDouble() ??
                ((data['hoursWorked'] as num?)?.toDouble() != null
                    ? (data['hoursWorked'] as num).toDouble() / 8
                    : 0.0);

            employees.add(Employee(
              id: doc.id,
              name: name,
              position: data['position'] as String? ?? 'Staff',
              dailyRate: dailyRate,
              daysWorked: daysWorked,
              bonus: (data['bonus'] as num?)?.toDouble() ?? 0.0,
              deductions: (data['deductions'] as num?)?.toDouble() ?? 0.0,
              status: data['status'] as String? ?? 'Pending',
              lastPaidAt: (data['lastPaidAt'] as Timestamp?)?.toDate(),
            ));
          } catch (e) {
            debugPrint('Error loading employee doc ${doc.id}: $e');
          }
        }

        // Auto-sync: Ensure every registered user with role == employee has an employee payroll record
        for (final u in users) {
          if (u.role == UserRole.employee && !existingEmployeeNames.contains(u.fullName)) {
            try {
              final empDocRef = FirebaseFirestore.instance.collection('employees').doc(u.id);
              await empDocRef.set({
                'name': u.fullName,
                'position': u.position ?? 'Staff',
                'dailyRate': 300.0,
                'daysWorked': 0.0,
                'bonus': 0.0,
                'deductions': 0.0,
                'status': 'Pending',
              });
              employees.add(Employee(
                id: u.id,
                name: u.fullName,
                position: u.position ?? 'Staff',
                dailyRate: 300.0,
                daysWorked: 0.0,
                bonus: 0.0,
                deductions: 0.0,
                status: 'Pending',
              ));
              existingEmployeeNames.add(u.fullName);
            } catch (e) {
              debugPrint('Error auto-syncing employee ${u.fullName}: $e');
            }
          }
        }
        notifyListeners();
      });
    }
  }

  Future<void> _loadPayrollHistory() async {
    if (!_payrollHistoryListenerSet) {
      _payrollHistoryListenerSet = true;
      FirebaseFirestore.instance.collection('payrollHistory').snapshots().listen((snapshot) {
        payrollHistory.clear();
        for (final doc in snapshot.docs) {
          try {
            final data = doc.data();
            payrollHistory.add(PayrollRecord(
              id: doc.id,
              employeeId: data['employeeId'] as String? ?? '',
              employeeName: data['employeeName'] as String? ?? '',
              position: data['position'] as String? ?? '',
              netSalary: (data['netSalary'] as num?)?.toDouble() ?? 0.0,
              status: data['status'] as String? ?? 'Paid',
              date: (data['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
            ));
          } catch (e) {
            debugPrint('Error loading payrollHistory doc ${doc.id}: $e');
          }
        }
        notifyListeners();
      });
    }
  }

  Future<void> _loadAttendance() async {
    if (!_attendanceListenerSet) {
      _attendanceListenerSet = true;
      FirebaseFirestore.instance.collection('attendance').snapshots().listen((snapshot) {
        attendance.clear();
        for (final doc in snapshot.docs) {
          try {
            final data = doc.data();
            attendance.add(AttendanceRecord(
              id: doc.id,
              employeeName: data['employeeName'] as String? ?? '',
              date: (data['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
              createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
              timeIn: data['timeIn'] as String? ?? '',
              timeOut: data['timeOut'] as String?,
              status: data['status'] as String? ?? 'Present',
              method: data['method'] as String? ?? 'RFID',
            ));
          } catch (e) {
            debugPrint('Error loading attendance doc ${doc.id}: $e');
          }
        }
        notifyListeners();
      });
      // Auto-close any shift left open past its 2:30 AM cutoff (e.g. the
      // employee forgot to scan out), then keep sweeping so it self-heals
      // even while nobody has the app open scanning.
      _startAttendanceSweep();
    }
  }

  /// A live listener (like [_loadKioskOrders]/[_loadNotifications]) so a
  /// feedback submitted from one session (e.g. a customer on "My Orders")
  /// is immediately reflected on the Admin and Employee Customer Feedback
  /// pages, and the submitting customer's own order card, without needing
  /// a manual refresh.
  Future<void> _loadFeedbacks() async {
    if (_feedbacksListenerSet) return;
    _feedbacksListenerSet = true;
    FirebaseFirestore.instance
        .collection('feedbacks')
        .snapshots()
        .listen((snapshot) {
      feedbacks.clear();
      for (final doc in snapshot.docs) {
        try {
          final data = doc.data();
          feedbacks.add(FeedbackRecord(
            id: doc.id,
            customerName: data['customerName'] as String? ?? '',
            rating: (data['rating'] as int?) ?? 0,
            comment: data['comment'] as String? ?? '',
            category: data['category'] as String? ?? '',
            date: (data['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
            status: data['status'] as String? ?? 'New',
            reply: data['reply'] as String?,
            customerId: data['customerId'] as String?,
            orderId: data['orderId'] as String?,
          ));
        } catch (e) {
          debugPrint('Error loading feedback doc ${doc.id}: $e');
        }
      }
      notifyListeners();
    });
  }

  /// Whether the given completed order (transaction ID) already has
  /// feedback attached — used to limit each order to one submission.
  bool hasFeedbackForOrder(String orderId) =>
      feedbacks.any((f) => f.orderId == orderId);

  /// The feedback (if any) left for a specific completed order, so it can
  /// be displayed directly on that order in "My Orders".
  FeedbackRecord? feedbackForOrder(String orderId) {
    try {
      return feedbacks.firstWhere((f) => f.orderId == orderId);
    } catch (_) {
      return null;
    }
  }

  String roleKey([String? roleOrName]) {
    if (currentUser != null) return currentUser!.id;
    final r = roleOrName?.trim().toLowerCase() ?? '';
    return r.isNotEmpty ? r : 'default';
  }

  final Map<String, Map<String, DateTime>> roleClearedTimestamps = {};

  Future<void> unhideConversationForMe(String conversationId, [String? roleOrName]) async {
    final key = roleKey(roleOrName);
    if (roleHiddenConversations.containsKey(key)) {
      roleHiddenConversations[key]!.remove(conversationId);
    }
    
    if (currentUser != null) {
      currentUser!.hiddenConversations.remove(conversationId);
      try {
        final firestoreMap = currentUser!.clearedConversations.map((k, v) => MapEntry(k, Timestamp.fromDate(v)));
        await FirebaseFirestore.instance.collection('users').doc(currentUser!.id).update({
          'hiddenConversations': currentUser!.hiddenConversations,
          'clearedConversations': firestoreMap,
        });
      } catch (e) {
        debugPrint('Error unhiding conversation: $e');
      }
    }
    notifyListeners();
  }

  void ensureConversationExists({
    required String id,
    required String withName,
    bool isGroup = false,
    List<String> members = const [],
    String? currentRoleOrName,
  }) {
    unhideConversationForMe(id, currentRoleOrName);

    final existingIndex = adminEmployeeChats.indexWhere((c) => c.id == id);
    if (existingIndex == -1) {
      adminEmployeeChats.add(Conversation(
        withName: withName,
        messages: [],
        isGroup: isGroup,
        id: id,
        members: members,
      ));
    } else {
      final old = adminEmployeeChats[existingIndex];
      if (old.members.isEmpty && members.isNotEmpty) {
        adminEmployeeChats[existingIndex] = Conversation(
          withName: old.withName,
          messages: old.messages,
          isGroup: old.isGroup,
          id: old.id,
          members: members,
          groupImageBase64: old.groupImageBase64,
        );
      }
    }
    notifyListeners();
  }

  Future<void> _loadAdminEmployeeChats() async {
    adminEmployeeChats.clear();
    
    // 1. Load Group Chats from Firestore
    try {
      final grpSnapshot = await FirebaseFirestore.instance.collection('groups').get();
      for (final gDoc in grpSnapshot.docs) {
        final gData = gDoc.data();
        final gName = gData['name'] as String? ?? 'Group Chat';
        final gMembers = List<String>.from(gData['members'] ?? []);
        final gImage = gData['groupImageBase64'] as String?;
        if (!adminEmployeeChats.any((c) => c.isGroup && c.id == gDoc.id)) {
          adminEmployeeChats.add(Conversation(
            withName: gName,
            messages: [],
            isGroup: true,
            id: gDoc.id,
            members: gMembers,
            groupImageBase64: gImage,
          ));
        } else {
          final idx = adminEmployeeChats.indexWhere((c) => c.isGroup && c.id == gDoc.id);
          if (idx != -1) {
            final old = adminEmployeeChats[idx];
            adminEmployeeChats[idx] = Conversation(
              withName: gName,
              messages: old.messages,
              isGroup: true,
              id: old.id,
              members: gMembers,
              groupImageBase64: gImage,
            );
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading group chats: $e');
    }

    // 2. Setup Real-time Listener for Messages
    if (!_messagesListenerSet) {
      _messagesListenerSet = true;
      bool isFirstLoad = true;
      FirebaseFirestore.instance
          .collection('messages')
          .orderBy('timestamp', descending: false)
          .snapshots()
          .listen((snapshot) {
            if (!isFirstLoad) {
              for (final change in snapshot.docChanges) {
                if (change.type == DocumentChangeType.added) {
                  final data = change.doc.data();
                  if (data != null) {
                    final sender = data['sender'] as String? ?? 'Someone';
                    final text = data['text'] as String? ?? '';
                    final fileName = data['fileName'] as String? ?? '';
                    final isAttachment = fileName.isNotEmpty || (data['imageUrl'] as String? ?? '').isNotEmpty;
                    final bodyText = text.isNotEmpty 
                        ? text 
                        : (isAttachment ? 'Sent an attachment' : 'Sent a message');
                    
                    // Only notify if an account is logged in AND current user is a participant of this conversation AND sender is NOT current user
                    if (currentUser != null) {
                      final currentUserName = currentUser!.fullName.trim().toLowerCase();
                      final currentRole = currentUser!.role;
                      final convoId = data['conversationId'] as String? ?? '';
                      
                      bool isParticipant = false;
                      for (final c in adminEmployeeChats) {
                        if (c.id == convoId) {
                          if (c.isGroup) {
                            isParticipant = c.members.any((m) => m.trim().toLowerCase() == currentUserName || (m.toLowerCase() == 'admin' && currentRole == UserRole.admin));
                          } else {
                            if (currentRole == UserRole.admin) {
                              isParticipant = true;
                            } else {
                              isParticipant = c.id.toLowerCase().contains(currentUserName) || c.withName.toLowerCase() == currentUserName;
                            }
                          }
                          break;
                        }
                      }
                      if (!isParticipant && currentRole == UserRole.admin) {
                        isParticipant = true;
                      } else if (!isParticipant && convoId.toLowerCase().contains(currentUserName)) {
                        isParticipant = true;
                      }

                      if (isParticipant && sender != _messagingSelfId && sender != currentUser?.fullName) {
                        NotificationService.showLocalNotification(
                          id: change.doc.id.hashCode,
                          title: 'New Message from $sender',
                          body: bodyText,
                        );
                      }
                    }
                  }
                }
              }
            }
            isFirstLoad = false;

            // Instead of clearing and losing references, let's clear sub message lists safely
            for (var c in adminEmployeeChats) {
              c.messages.clear();
            }

            for (final doc in snapshot.docs) {
              final data = doc.data();
              final employeeName = data['employeeName'] as String? ?? '';
              final sender = data['sender'] as String? ?? '';
              final text = data['text'] as String? ?? '';
              final imageUrlRaw = data['imageUrl'] as String? ?? '';
              final imageUrl = imageUrlRaw.isNotEmpty ? imageUrlRaw : null;
              final fileNameRaw = data['fileName'] as String? ?? '';
              final fileName = fileNameRaw.isNotEmpty ? fileNameRaw : null;
              final fileDataRaw = data['fileData'] as String? ?? '';
              final fileData = fileDataRaw.isNotEmpty ? fileDataRaw : null;
              final timestamp = (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now();
              final read = data['read'] as bool? ?? false;
              final isGroupMsg = data['isGroup'] as bool? ?? false;
              final msgGroupId = data['groupId'] as String? ?? '';
              final conversationId = data['conversationId'] as String? ?? '';
              final deletedFor = List<String>.from(data['deletedFor'] as List? ?? const []);

              // "Delete for You" hides this message only for the viewer whose
              // name is in deletedFor; everyone else still sees it normally.
              if (deletedFor.contains(_messagingSelfId)) {
                continue;
              }

              Conversation? convo;
              if (isGroupMsg && msgGroupId.isNotEmpty) {
                var found = adminEmployeeChats.where((c) => c.isGroup && c.id == msgGroupId);
                if (found.isNotEmpty) {
                  convo = found.first;
                } else {
                  final newConvo = Conversation(withName: 'Group Chat', messages: [], isGroup: true, id: msgGroupId);
                  adminEmployeeChats.add(newConvo);
                  convo = newConvo;
                }
              } else if (conversationId.isNotEmpty) {
                var found = adminEmployeeChats.where((c) => c.id == conversationId);
                if (found.isNotEmpty) {
                  convo = found.first;
                } else {
                  String name = employeeName;
                  List<String> members = [];
                  if (conversationId.startsWith('p2p_Admin_')) {
                    name = conversationId.replaceFirst('p2p_Admin_', '');
                    members = ['Admin', name];
                  } else if (conversationId.startsWith('p2p_')) {
                    final parts = conversationId.replaceFirst('p2p_', '').split('_');
                    members = List<String>.from(parts);
                    if (name.isEmpty && parts.length >= 2) {
                      name = parts[1];
                    }
                  }
                  if (name.isEmpty) name = 'Personal Chat';
                  final newConvo = Conversation(
                    withName: name,
                    messages: [],
                    isGroup: false,
                    id: conversationId,
                    members: members,
                  );
                  adminEmployeeChats.add(newConvo);
                  convo = newConvo;
                }
              }

              if (convo != null) {
                convo.messages.add(ChatMessage(
                  id: doc.id,
                  sender: sender,
                  text: text,
                  imageUrl: imageUrl,
                  fileName: fileName,
                  fileData: fileData,
                  timestamp: timestamp,
                  read: read,
                  deletedFor: deletedFor,
                ));
              }
            }
            notifyListeners();
          });
    }
  }

  Future<void> sendAdminEmployeeMessage(String employeeName, String sender, String text) async {
    // For backwards compatibility
    String convoId = 'p2p_Admin_$employeeName';
    var found = adminEmployeeChats.where((c) => c.withName == employeeName || c.id == convoId);
    if (found.isNotEmpty) {
      convoId = found.first.id;
    }
    await sendMessage(conversationId: convoId, sender: sender, text: text, convoName: employeeName);
  }

  Future<void> sendMessage({
    required String conversationId,
    required String sender,
    required String text,
    String? imageUrl,
    String? fileName,
    String? fileData,
    bool isGroup = false,
    String groupId = '',
    String convoName = '',
  }) async {
    try {
      // If conversationId is empty but convoName is given, build standard fallback id
      final computedConvoId = conversationId.isNotEmpty 
          ? conversationId 
          : (isGroup ? groupId : 'p2p_Admin_$convoName');

      if (currentUser != null && currentUser!.hiddenConversations.contains(computedConvoId)) {
        currentUser!.hiddenConversations.remove(computedConvoId);
        try {
          await FirebaseFirestore.instance.collection('users').doc(currentUser!.id).update({
            'hiddenConversations': currentUser!.hiddenConversations,
          });
        } catch (_) {}
      }

      await FirebaseFirestore.instance.collection('messages').add({
        'employeeName': convoName,
        'sender': sender,
        'text': text,
        'imageUrl': imageUrl ?? '',
        'fileName': fileName ?? '',
        'fileData': fileData ?? '',
        'timestamp': FieldValue.serverTimestamp(),
        'read': false,
        'isGroup': isGroup,
        'groupId': isGroup ? computedConvoId : '',
        'conversationId': computedConvoId,
      });

      // Avoid calling full heavy reload _initializeFromFirestore() here which blocks the sync stream
      // Let the Firestore snapshot listener capture the newly added document naturally in real-time
    } catch (e) {
      debugPrint('Error sending message: $e');
    }
  }

  Future<void> createGroupChat(String groupName, List<String> memberNames, {String? groupImageBase64}) async {
    try {
      final docRef = await FirebaseFirestore.instance.collection('groups').add({
        'name': groupName,
        'members': memberNames,
        'groupImageBase64': groupImageBase64 ?? '',
        'createdAt': FieldValue.serverTimestamp(),
      });
      
      final newGroup = Conversation(
        withName: groupName,
        messages: [],
        isGroup: true,
        id: docRef.id,
        members: memberNames,
        groupImageBase64: groupImageBase64,
      );

      if (!adminEmployeeChats.any((c) => c.isGroup && c.id == docRef.id)) {
        adminEmployeeChats.add(newGroup);
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Error creating group chat: $e');
    }
  }

  Future<void> updateGroupDetails(String groupId, {List<String>? memberNames, String? groupName, String? groupImageBase64}) async {
    try {
      final updates = <String, dynamic>{};
      if (memberNames != null) updates['members'] = memberNames;
      if (groupName != null) updates['name'] = groupName;
      if (groupImageBase64 != null) updates['groupImageBase64'] = groupImageBase64;

      if (updates.isNotEmpty) {
        await FirebaseFirestore.instance.collection('groups').doc(groupId).update(updates);
        final idx = adminEmployeeChats.indexWhere((c) => c.isGroup && c.id == groupId);
        if (idx != -1) {
          final old = adminEmployeeChats[idx];
          adminEmployeeChats[idx] = Conversation(
            withName: groupName ?? old.withName,
            messages: old.messages,
            isGroup: true,
            id: old.id,
            members: memberNames ?? old.members,
            groupImageBase64: groupImageBase64 ?? old.groupImageBase64,
          );
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('Error updating group details: $e');
    }
  }

  Future<void> updateGroupMembers(String groupId, List<String> memberNames) async {
    await updateGroupDetails(groupId, memberNames: memberNames);
  }

  /// The identity string a message's "deletedFor"/"sender" fields use for the
  /// currently logged-in user — 'Admin' for the admin account, otherwise
  /// their full name — matching the `currentRole` each messaging screen is
  /// built with.
  String get _messagingSelfId {
    final cu = currentUser;
    if (cu == null) return '';
    return cu.fullName.trim().isNotEmpty ? cu.fullName.trim() : (cu.role == UserRole.admin ? 'Admin' : cu.fullName);
  }

  /// Deletes a single message for both sides of the conversation by removing
  /// its document from Firestore entirely, so it stays gone for everyone
  /// after a refresh or re-login.
  Future<void> deleteMessageForEveryone(String messageId) async {
    if (messageId.isEmpty) return;
    try {
      await FirebaseFirestore.instance
          .collection('messages')
          .doc(messageId)
          .delete();
    } catch (e) {
      debugPrint('Error deleting message for everyone: $e');
    }
  }

  /// Hides a single message only for the current user by recording their
  /// identity on the message's "deletedFor" list. The message document (and
  /// everyone else's copy of it) is left untouched, and the hide persists
  /// across refreshes/re-logins since it's saved on the message itself.
  Future<void> deleteMessageForMe(String messageId) async {
    if (messageId.isEmpty) return;
    final selfId = _messagingSelfId;
    if (selfId.isEmpty) return;
    try {
      await FirebaseFirestore.instance
          .collection('messages')
          .doc(messageId)
          .update({
        'deletedFor': FieldValue.arrayUnion([selfId]),
      });
    } catch (e) {
      debugPrint('Error deleting message for you: $e');
    }
  }

  Future<void> markMessagesAsRead(String conversationId, String currentRole) async {
    try {
      // Look up non-read messages for this specific conversation channel
      final snapshot = await FirebaseFirestore.instance
          .collection('messages')
          .where('conversationId', isEqualTo: conversationId)
          .where('read', isEqualTo: false)
          .get();

      final batch = FirebaseFirestore.instance.batch();
      bool hasUpdates = false;

      for (final doc in snapshot.docs) {
        final sender = doc.data()['sender'] as String? ?? '';
        if (sender != currentRole) {
          batch.update(doc.reference, {'read': true});
          hasUpdates = true;
        }
      }

      if (hasUpdates) {
        await batch.commit();
        // Crucial local list status sync so it reflects state changes immediately before next listen callback fires
        for (var c in adminEmployeeChats) {
          if (c.id == conversationId) {
            for (var m in c.messages) {
              if (m.sender != currentRole) {
                m.read = true;
              }
            }
          }
        }
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error marking messages as read: $e');
    }
  }

  /// Deletes a single conversation (and only that conversation) along with
  /// all of its chat messages. For group chats, the group document itself is
  /// removed so it disappears from every member's list. For 1:1 chats
  /// (Admin<->Employee or Employee<->Employee), the thread is tied to the
  /// existing user accounts, so only its message history is cleared; the
  /// conversation slot itself remains available for future messages, same
  /// as a brand-new, never-messaged chat.
  Future<void> clearConversationForMe(String conversationId, [String? roleOrName]) async {
    final now = DateTime.now();
    final key = roleKey(roleOrName);

    if (!roleHiddenConversations.containsKey(key)) {
      roleHiddenConversations[key] = [];
    }
    if (!roleHiddenConversations[key]!.contains(conversationId)) {
      roleHiddenConversations[key]!.add(conversationId);
    }

    roleClearedTimestamps[key] ??= {};
    roleClearedTimestamps[key]![conversationId] = now;

    if (currentUser != null) {
      currentUser!.clearedConversations[conversationId] = now;
      if (!currentUser!.hiddenConversations.contains(conversationId)) {
        currentUser!.hiddenConversations.add(conversationId);
      }
      try {
        final firestoreMap = currentUser!.clearedConversations.map((k, v) => MapEntry(k, Timestamp.fromDate(v)));
        await FirebaseFirestore.instance.collection('users').doc(currentUser!.id).update({
          'clearedConversations': firestoreMap,
          'hiddenConversations': currentUser!.hiddenConversations,
        });
      } catch (e) {
        debugPrint('Error clearing conversation: $e');
      }
    }
    notifyListeners();
  }

  bool isConversationHiddenForMe(String conversationId, [String? roleOrName]) {
    final key = roleKey(roleOrName);
    if (roleHiddenConversations[key]?.contains(conversationId) == true) return true;
    if (currentUser?.hiddenConversations.contains(conversationId) == true) return true;
    return false;
  }

  DateTime? getRoleClearedTimestamp(String conversationId, [String? roleOrName]) {
    final key = roleKey(roleOrName);
    if (roleClearedTimestamps[key]?.containsKey(conversationId) == true) {
      return roleClearedTimestamps[key]![conversationId];
    }
    if (currentUser != null && currentUser!.clearedConversations.containsKey(conversationId)) {
      return currentUser!.clearedConversations[conversationId];
    }
    return null;
  }

  Future<void> deleteConversation(String conversationId,
      {bool isGroup = false}) async {
    await clearConversationForMe(conversationId, currentUser?.fullName);
  }

  Future<void> _loadPettyCash() async {
    if (!_pettyCashListenerSet) {
      _pettyCashListenerSet = true;
      try {
        final cfgDoc = await FirebaseFirestore.instance.collection('pettyCashConfig').doc('settings').get();
        if (cfgDoc.exists) {
          final config = cfgDoc.data() ?? {};
          final daily = config['dailyStartingBalances'];
          if (daily is Map) {
            for (final entry in daily.entries) {
              final value = (entry.value as num?)?.toDouble();
              if (value != null) pettyCashDailyStarts[entry.key.toString()] = value;
            }
          }
          final val = (config['startingBalance'] as num?)?.toDouble();
          if (val != null) {
            pettyCashDailyStarts.putIfAbsent(pettyCashShiftKey(DateTime.now()), () => val);
          }
        }
      } catch (e) {
        debugPrint('Error loading pettyCashConfig: $e');
      }

      FirebaseFirestore.instance.collection('pettyCash').snapshots().listen((snapshot) {
        pettyCash.clear();
        for (final doc in snapshot.docs) {
          try {
            final data = doc.data();
            pettyCash.add(PettyCashEntry(
              id: doc.id,
              description: data['description'] as String? ?? '',
              category: data['category'] as String? ?? '',
              amount: (data['amount'] as num?)?.toDouble() ?? 0.0,
              date: (data['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
            ));
          } catch (e) {
            debugPrint('Error loading pettyCash doc ${doc.id}: $e');
          }
        }
        notifyListeners();
      });
    }
  }

  Future<void> _loadProcurement() async {
    if (!_procurementListenerSet) {
      _procurementListenerSet = true;
      FirebaseFirestore.instance.collection('procurement').snapshots().listen((snapshot) {
        procurement.clear();
        for (final doc in snapshot.docs) {
          try {
            final data = doc.data();
            procurement.add(ProcurementRecord(
              id: doc.id,
              productName: data['productName'] as String? ?? '',
              supplier: data['supplier'] as String? ?? '',
              quantity: (data['quantity'] as int?) ?? 0,
              cost: (data['cost'] as num?)?.toDouble() ?? 0.0,
              date: (data['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
              status: data['status'] as String? ?? 'Restocked',
              itemType: data['itemType'] as String? ?? 'Inventory Item',
              expiration: (data['expiration'] as Timestamp?)?.toDate(),
            ));
          } catch (e) {
            debugPrint('Error loading procurement doc ${doc.id}: $e');
          }
        }
        notifyListeners();
      });
    }
  }

  Future<void> _loadPromotions() async {
    final snapshot =
        await FirebaseFirestore.instance.collection('promotions').get();
    for (final doc in snapshot.docs) {
      try {
        final data = doc.data();
        promotions.add(PromotionRecord(
          productName: data['productName'] as String? ?? '',
          promoType: data['promoType'] as String? ?? '',
          createdAt:
              (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
        ));
      } catch (e) {
        debugPrint('Error loading promotion doc ${doc.id}: $e');
      }
    }
  }

  Future<void> _loadNotifications() async {
    if (!_notificationsListenerSet) {
      _notificationsListenerSet = true;
      // A live listener (rather than a one-time get) so a low-stock/out-of-
      // stock alert raised from one session (e.g. a POS sale) is pushed to
      // every other open session — Admin and Employee alike — immediately.
      FirebaseFirestore.instance
          .collection('notifications')
          .orderBy('time', descending: true)
          .limit(50)
          .snapshots()
          .listen((snapshot) {
        notifications.clear();
        for (final doc in snapshot.docs) {
          try {
            final data = doc.data();
            notifications.add(AppNotification(
              title: data['title'] as String? ?? '',
              body: data['body'] as String? ?? '',
              type: data['type'] as String? ?? '',
              time: (data['time'] as Timestamp?)?.toDate() ?? DateTime.now(),
              read: data['read'] as bool? ?? false,
            ));
          } catch (e) {
            debugPrint('Error loading notification doc ${doc.id}: $e');
          }
        }
        notifyListeners();
      });
    }
  }

  Future<void> _loadArchive() async {
    if (!_archiveListenerSet) {
      _archiveListenerSet = true;
      FirebaseFirestore.instance.collection('archive').snapshots().listen((snapshot) {
        archive.clear();
        for (final doc in snapshot.docs) {
          try {
            final data = doc.data();
            AppUser? originalUser;
            final originalUserId = data['originalUserId'] as String?;
            if (originalUserId != null && originalUserId.isNotEmpty) {
              for (final u in users) {
                if (u.id == originalUserId) {
                  originalUser = u;
                  break;
                }
              }
            }

            archive.add(ArchivedRecord(
              id: doc.id,
              category: data['category'] as String? ?? 'Unknown',
              name: data['name'] as String? ?? '',
              email: data['email'] as String? ?? '',
              role: data['role'] as String? ?? '',
              dateArchived: (data['dateArchived'] as Timestamp?)?.toDate() ?? DateTime.now(),
              archivedBy: data['archivedBy'] as String? ?? 'Unknown',
              originalUser: originalUser,
              originalCustomerId: data['originalCustomerId'] as String?,
            ));
          } catch (e) {
            debugPrint('Error loading archive doc ${doc.id}: $e');
          }
        }
        notifyListeners();
      });
    }
  }

  /// Parses the `addOns` list stored on a cart-line map (kioskOrders /
  /// transactions item, or a kioskOrder's raw item data) back into
  /// [MenuAddOn]s. Shared by every place that reconstructs a [CartItem]
  /// from Firestore so add-ons picked at the POS/Kiosk survive through
  /// order acceptance, receipts, and transaction history.
  List<MenuAddOn> _parseAddOns(dynamic raw) {
    if (raw is! List) return [];
    final result = <MenuAddOn>[];
    for (final a in raw) {
      if (a is Map) {
        result.add(MenuAddOn.fromMap(Map<String, dynamic>.from(a)));
      }
    }
    return result;
  }

  Future<void> _loadKioskOrders() async {
    if (!_kioskOrdersListenerSet) {
      _kioskOrdersListenerSet = true;
      FirebaseFirestore.instance.collection('kioskOrders').snapshots().listen((snapshot) {
        if (!_kioskOrdersInitialLoad) {
          for (final change in snapshot.docChanges) {
            final data = change.doc.data();
            if (data != null) {
              final status = data['status'] as String? ?? 'Pending';
              final orderNumber = data['orderNumber'] as String? ?? '';
              final customerId = data['customerId'] as String?;

              if (change.type == DocumentChangeType.added) {
                if (currentUser?.role == UserRole.employee || currentUser?.role == UserRole.admin) {
                  NotificationService.showLocalNotification(
                    id: change.doc.id.hashCode,
                    title: 'New Order Received',
                    body: 'Order #$orderNumber has been placed.',
                  );
                }
              } else if (change.type == DocumentChangeType.modified) {
                if (status == 'Ready' && customerId != null && customerId == currentUser?.id) {
                  NotificationService.showLocalNotification(
                    id: change.doc.id.hashCode,
                    title: 'Order Ready!',
                    body: 'Your order #$orderNumber is now ready for pickup.',
                  );
                }
              }
            }
          }
        }
        _kioskOrdersInitialLoad = false;
        kioskOrders.clear();
        for (final doc in snapshot.docs) {
          try {
            final data = doc.data();
            final itemsData = data['items'] as List<dynamic>?;
            final List<CartItem> items = [];
            if (itemsData != null) {
              for (final itemData in itemsData) {
                try {
                  final itemMap = itemData as Map<String, dynamic>;
                  final productId = itemMap['productId'] as String?;
                  final productName = itemMap['productName'] as String?;
                  final quantity = (itemMap['quantity'] as num?)?.toInt() ?? 0;
                  final unitPrice =
                      (itemMap['unitPrice'] as num?)?.toDouble() ?? 0.0;

                  Product? product;
                  if (productId != null && productId.isNotEmpty) {
                    try {
                      product = products.firstWhere((p) => p.id == productId);
                    } catch (e) {
                      product = null;
                    }
                  }

                  if (product == null &&
                      productName != null &&
                      productName.isNotEmpty) {
                    try {
                      product = products.firstWhere((p) => p.name == productName);
                    } catch (e) {
                      product = null;
                    }
                  }

                  if (product == null) {
                    String fallbackId = 'fallback_';
                    if (productId != null && productId.isNotEmpty) {
                      fallbackId += productId.hashCode.toString();
                    } else if (productName != null && productName.isNotEmpty) {
                      fallbackId += productName.hashCode.toString();
                    } else {
                      fallbackId +=
                          'unknown_${DateTime.now().millisecondsSinceEpoch}';
                    }

                    product = Product(
                      id: fallbackId,
                      name: productName ?? 'Unknown Product',
                      category: 'Unknown',
                      price: unitPrice,
                      description: '',
                      emoji: '',
                    );
                  }

                  items.add(CartItem(
                    product: product,
                    quantity: quantity,
                    selectedAddOns: _parseAddOns(itemMap['addOns']),
                  ));
                } catch (e) {
                  debugPrint('Error loading kiosk order item: $e');
                }
              }
            }
            kioskOrders.add(OrderRecord(
              id: doc.id,
              items: items,
              source: data['source'] as String? ?? 'Unknown',
              status: data['status'] as String? ?? 'Pending',
              createdAt:
                  (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
              customerName: data['customerName'] as String?,
              discount: (data['discount'] as num?)?.toDouble() ?? 0.0,
              customerId: data['customerId'] as String?,
              paymentMethod:
                  data['paymentMethod'] as String? ?? 'Cash',
              orderNumber: data['orderNumber'] as String?,
              proofOfPaymentBase64: data['proofOfPaymentBase64'] as String?,
              declineReason: data['declineReason'] as String?,
              expiresAt: (data['expiresAt'] as Timestamp?)?.toDate(),
              orderType: data['orderType'] as String? ?? 'Dine In',
              verifiedTotal: (data['verifiedTotal'] as num?)?.toDouble(),
              extractedAmount: (data['extractedAmount'] as num?)?.toDouble(),
              extractedReferenceId: data['extractedReferenceId'] as String?,
              extractedDateTime: data['extractedDateTime'] as String?,
              partialAmountPaid: (data['partialAmountPaid'] as num?)?.toDouble(),
              additionalPaymentsPaid: (data['additionalPaymentsPaid'] as num?)?.toDouble(),
              receipt: data['receipt'] is Map
                  ? ReceiptRecord.fromMap(
                      Map<String, dynamic>.from(data['receipt'] as Map))
                  : null,
              isGuest: data['isGuest'] as bool? ?? false,
              tableNumber: data['tableNumber'] as String?,
            ));
          } catch (e) {
            debugPrint('Error loading kiosk order doc ${doc.id}: $e');
          }
        }
        notifyListeners();
      });
      // Expire any orders whose countdown lapsed while the app was closed,
      // then keep sweeping so they disappear from Pending Orders on time.
      _startExpirySweep();
    }
  }

  Future<void> _loadTransactions() async {
    if (!_transactionsListenerSet) {
      _transactionsListenerSet = true;
      FirebaseFirestore.instance.collection('transactions').snapshots().listen((snapshot) {
        transactions.clear();
        for (final doc in snapshot.docs) {
          try {
            final data = doc.data();
            final itemsData = data['items'] as List<dynamic>?;
            final List<CartItem> items = [];
            if (itemsData != null) {
              for (final itemData in itemsData) {
                try {
                  final itemMap = itemData as Map<String, dynamic>;
                  final productId = itemMap['productId'] as String?;
                  final productName = itemMap['productName'] as String?;
                  final quantity = (itemMap['quantity'] as num?)?.toInt() ?? 0;
                  final unitPrice =
                      (itemMap['unitPrice'] as num?)?.toDouble() ?? 0.0;

                  Product? product;
                  if (productId != null && productId.isNotEmpty) {
                    try {
                      product = products.firstWhere((p) => p.id == productId);
                    } catch (e) {
                      product = null;
                    }
                  }

                  if (product == null &&
                      productName != null &&
                      productName.isNotEmpty) {
                    try {
                      product = products.firstWhere((p) => p.name == productName);
                    } catch (e) {
                      product = null;
                    }
                  }

                  if (product == null) {
                    String fallbackId = 'fallback_';
                    if (productId != null && productId.isNotEmpty) {
                      fallbackId += productId.hashCode.toString();
                    } else if (productName != null && productName.isNotEmpty) {
                      fallbackId += productName.hashCode.toString();
                    } else {
                      fallbackId +=
                          'unknown_${DateTime.now().millisecondsSinceEpoch}';
                    }

                    product = Product(
                      id: fallbackId,
                      name: productName ?? 'Unknown Product',
                      category: 'Unknown',
                      price: unitPrice,
                      description: '',
                      emoji: '',
                    );
                  }

                  items.add(CartItem(
                    product: product,
                    quantity: quantity,
                    selectedAddOns: _parseAddOns(itemMap['addOns']),
                  ));
                } catch (e) {
                  debugPrint('Error loading transaction item: $e');
                }
              }
            }
            transactions.add(TransactionRecord(
              id: doc.id,
              items: items,
              subtotal: (data['subtotal'] as num?)?.toDouble() ?? 0.0,
              discount: (data['discount'] as num?)?.toDouble() ?? 0.0,
              total: (data['total'] as num?)?.toDouble() ?? 0.0,
              timestamp:
                  (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
              cashier: data['cashier'] as String? ?? 'Unknown',
              customerId: data['customerId'] as String?,
              customerName: data['customerName'] as String?,
              paymentMethod: data['paymentMethod'] as String?,
              orderNumber: data['orderNumber'] as String?,
              receipt: data['receipt'] is Map
                  ? ReceiptRecord.fromMap(
                      Map<String, dynamic>.from(data['receipt'] as Map))
                  : null,
              isGuest: data['isGuest'] as bool? ?? false,
              tableNumber: data['tableNumber'] as String?,
              archivedByAdmin: data['archivedByAdmin'] as bool? ?? false,
            ));
          } catch (e) {
            debugPrint('Error loading transaction doc ${doc.id}: $e');
          }
        }
        notifyListeners();
      });
    }
  }

  ({DateTime start, DateTime end}) get currentShiftWindow {
    final now = DateTime.now();
    final today630PM = DateTime(now.year, now.month, now.day, 18, 30);

    DateTime start;
    if (now.isAfter(today630PM) || now.isAtSameMomentAs(today630PM)) {
      start = today630PM;
    } else {
      start = today630PM.subtract(const Duration(days: 1));
    }
    final end = start.add(const Duration(hours: 8));
    return (start: start, end: end);
  }

  /// Returns the shift date (time zeroed) that a given timestamp belongs to.
  /// Café operating shift runs from 7:00 PM (19:00) to 2:00 AM next day.
  /// - Orders between 7:00 PM today and 11:59 PM today -> belongs to today's shift (date = today).
  /// - Orders between 12:00 AM (midnight) and 2:00 AM today -> belongs to yesterday's shift (date = yesterday).
  /// - Orders placed outside cafe hours (e.g. 2:00 AM to 6:59 PM) -> belongs to yesterday's shift (date = yesterday).
  DateTime getShiftDateForTimestamp(DateTime timestamp) {
    if (timestamp.hour >= 19) {
      return DateTime(timestamp.year, timestamp.month, timestamp.day);
    } else {
      final dateOnly = DateTime(timestamp.year, timestamp.month, timestamp.day);
      return dateOnly.subtract(const Duration(days: 1));
    }
  }

  double get todaySales {
    final currentShift = getShiftDateForTimestamp(DateTime.now());
    double total = 0.0;
    for (final t in transactions) {
      if (t.archivedByAdmin) continue;
      final tShift = getShiftDateForTimestamp(t.timestamp);
      if (tShift.year == currentShift.year &&
          tShift.month == currentShift.month &&
          tShift.day == currentShift.day) {
        total += t.total;
      }
    }
    return total;
  }

  double get totalSales {
    double total = 0.0;
    for (final t in transactions) {
      if (t.archivedByAdmin) continue;
      total += t.total;
    }
    return total;
  }

  // ===================== AUTH =====================

  /// Makes sure at least one admin account exists in Firestore.
  /// Safe to call on every app startup — it's a no-op once an admin
  /// already exists, so it will never create duplicates.
  Future<void> ensureDefaultAdmin() async {
    try {
      final existing = await FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'admin')
          .limit(1)
          .get();

      if (existing.docs.isNotEmpty) return; // an admin already exists

      await FirebaseFirestore.instance.collection('users').add({
        'fullName': 'Admin',
        'email': 'binimikha108@gmail.com',
        'phone': '0917-000-0000',
        'role': 'admin',
        'dateRegistered': FieldValue.serverTimestamp(),
        'password': 'Altair@1', // TODO: In production, hash this password!
        'status': 'Active', // active immediately, no OTP needed
      });
      debugPrint('AppData.ensureDefaultAdmin: default admin created.');
    } catch (e) {
      debugPrint('AppData.ensureDefaultAdmin error: $e');
    }
  }

  Future<AppUser?> login(String email, String password) async {
    try {
      final query = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: email.toLowerCase())
          .where('password', isEqualTo: password)
          .where('status', isEqualTo: 'Active')
          .limit(1)
          .get();

      if (query.docs.isEmpty) return null;

      final userDoc = query.docs.first;
      final userData = userDoc.data();
      final user = AppUser(
        id: userDoc.id,
        fullName: userData['fullName'] as String,
        email: userData['email'] as String,
        phone: userData['phone'] as String,
        role: _parseUserRole(userData['role'] as String),
        status: userData['status'] as String,
        dateRegistered: (userData['dateRegistered'] as Timestamp).toDate(),
        password: userData['password'] as String,
        position: userData['position'] as String?,
        employeeId: userData['employeeId'] as String?,
        profileImage: userData['profileImage'] as String?,
        otpCode: userData['otpCode'] as String?,
        otpExpiry: (userData['otpExpiry'] as Timestamp?)?.toDate(),
      );
      currentUser = user;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('saved_email', email);
        await prefs.setString('saved_password', password);
      } catch (e) {
        debugPrint('Error saving session: $e');
      }
      unawaited(NotificationService.subscribeToRoleTopics(currentUser?.role));
      notifyListeners();
      return currentUser;
    } catch (e) {
      // Surface the real cause in logs instead of only showing the
      // generic "Invalid email or password" message to the user.
      debugPrint('AppData.login error: $e');
      return null;
    }
  }

  Future<String?> checkLoginStatus(String email, String password) async {
    try {
      final query = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: email.toLowerCase())
          .where('password', isEqualTo: password)
          .limit(1)
          .get();

      if (query.docs.isEmpty) return 'Invalid email or password';
      final status = query.docs.first.data()['status'] as String? ?? 'Active';
      if (status != 'Active') {
        return 'Account status is "$status". Only Active accounts can log in.';
      }
      return null;
    } catch (_) {
      return 'Invalid email or password';
    }
  }

  UserRole _parseUserRole(String roleString) {
    switch (roleString) {
      case 'admin':
        return UserRole.admin;
      case 'employee':
        return UserRole.employee;
      case 'customer':
        return UserRole.customer;
      default:
        return UserRole.customer; // default fallback
    }
  }

  Future<void> restoreSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final email = prefs.getString('saved_email');
      final password = prefs.getString('saved_password');
      if (email != null && password != null) {
        await login(email, password);
      }
    } catch (e) {
      debugPrint('Error restoring session: $e');
    }
  }

  Future<void> logout() async {
    currentUser = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('saved_email');
      await prefs.remove('saved_password');
    } catch (e) {
      debugPrint('Error clearing session on logout: $e');
    }
    unawaited(NotificationService.unsubscribeFromTopics());
    notifyListeners();
  }

  /// Checks both active and pending registrations so duplicate prevention does
  /// not depend on whether the realtime listeners have finished loading.
  /// A phone number may be used by at most three registrations in total.
  Future<String?> validateRegistrationAvailability({
    required String email,
    required String phone,
  }) async {
    final cleanEmail = email.trim().toLowerCase();
    final cleanPhone = phone.trim();

    try {
      final emailQueries = await Future.wait([
        FirebaseFirestore.instance
            .collection('users')
            .where('email', isEqualTo: cleanEmail)
            .limit(1)
            .get(),
        FirebaseFirestore.instance
            .collection('pendingRegistrations')
            .where('email', isEqualTo: cleanEmail)
            .limit(1)
            .get(),
      ]);
      if (emailQueries.any((query) => query.docs.isNotEmpty)) {
        return 'This email is already registered';
      }

      final phoneQueries = await Future.wait([
        FirebaseFirestore.instance
            .collection('users')
            .where('phone', isEqualTo: cleanPhone)
            .get(),
        FirebaseFirestore.instance
            .collection('pendingRegistrations')
            .where('phone', isEqualTo: cleanPhone)
            .get(),
      ]);
      final phoneRegistrations = phoneQueries.fold<int>(
        0,
        (total, query) => total + query.docs.length,
      );
      if (phoneRegistrations >= 3) {
        return 'This phone number has reached the maximum of 3 registrations';
      }
      return null;
    } catch (e) {
      throw const RegistrationValidationException(
        'Unable to verify email and phone availability. Please try again.',
      );
    }
  }

  /// Creates the pending user, generates a real OTP, and emails it via
  /// Gmail SMTP. Throws [EmailSendException] if the email fails to send
  /// (the user is still created with 'Pending Verification' status, and
  /// the caller can offer to resend).
  Future<AppUser> register({
    String? firstName,
    String? lastName,
    String? fullName,
    required String email,
    required String phone,
    required String password,
    UserRole role = UserRole.customer,
  }) async {
    final fn = firstName?.trim() ?? '';
    final ln = lastName?.trim() ?? '';
    final computedFullName = (fullName != null && fullName.trim().isNotEmpty)
        ? fullName.trim()
        : '$fn $ln'.trim();
    final cleanEmail = email.trim().toLowerCase();
    final cleanPhone = phone.trim();

    try {
      final availabilityError = await validateRegistrationAvailability(
        email: cleanEmail,
        phone: cleanPhone,
      );
      if (availabilityError != null) {
        throw RegistrationValidationException(availabilityError);
      }

      // Create pending registration in 'pendingRegistrations' collection so
      // unverified users do NOT show up in the 'users' database or admin list
      final pendingDoc = await FirebaseFirestore.instance.collection('pendingRegistrations').add({
        'firstName': fn,
        'lastName': ln,
        'fullName': computedFullName,
        'email': cleanEmail,
        'phone': cleanPhone,
        'role': role.toString().split('.').last, // 'admin', 'employee', or 'customer'
        'dateRegistered': FieldValue.serverTimestamp(),
        'password': password,
        'status': 'Pending Verification',
      });

      final user = AppUser(
        id: pendingDoc.id,
        fullName: computedFullName,
        firstName: fn,
        lastName: ln,
        email: cleanEmail,
        phone: cleanPhone,
        role: role,
        status: 'Pending Verification',
        dateRegistered: DateTime.now(),
        password: password,
      );

      lastOtpError = null;
      try {
        await _generateAndSendOtpForPending(pendingDoc.id, user);
      } catch (e) {
        debugPrint('Error sending OTP email during registration: $e');
        lastOtpError = e.toString();
      }
      return user;
    } catch (e) {
      rethrow;
    }
  }

  /// Set by [register]/[resendOtp] when the most recent OTP email attempt
  /// failed, so the user can surface it. `null` means the last attempt (or
  /// none yet) succeeded.
  String? lastOtpError;

  Future<void> _generateAndSendOtpForPending(String pendingId, AppUser user) async {
    final otp = EmailService.instance.generateOtp();
    user.otpCode = otp;
    user.otpExpiry = DateTime.now().add(const Duration(minutes: 5));

    try {
      await FirebaseFirestore.instance.collection('pendingRegistrations').doc(pendingId).update({
        'otpCode': otp,
        'otpExpiry': user.otpExpiry,
      });
    } catch (e) {
      throw EmailSendException('Failed to save OTP to database: $e');
    }

    await EmailService.instance.sendOtpEmail(
      toEmail: user.email,
      toName: user.fullName,
      otp: otp,
    );
  }

  Future<void> _generateAndSendOtp(AppUser user) async {
    final otp = EmailService.instance.generateOtp();
    user.otpCode = otp;
    user.otpExpiry = DateTime.now().add(const Duration(minutes: 5));
    notifyListeners();

    try {
      await FirebaseFirestore.instance.collection('users').doc(user.id).update({
        'otpCode': otp,
        'otpExpiry': user.otpExpiry,
      });
    } catch (e) {
      throw EmailSendException('Failed to save OTP to database: $e');
    }

    await EmailService.instance.sendOtpEmail(
      toEmail: user.email,
      toName: user.fullName,
      otp: otp,
    );
  }

  Future<void> resendOtp(String id) async {
    try {
      final pendingDoc = await FirebaseFirestore.instance
          .collection('pendingRegistrations')
          .doc(id)
          .get();

      if (pendingDoc.exists) {
        final data = pendingDoc.data()!;
        final user = AppUser(
          id: id,
          fullName: data['fullName'] as String? ?? '',
          email: data['email'] as String? ?? '',
          phone: data['phone'] as String? ?? '',
          role: UserRole.customer,
          status: 'Pending Verification',
          dateRegistered: DateTime.now(),
          password: data['password'] as String? ?? '',
        );

        lastOtpError = null;
        try {
          await _generateAndSendOtpForPending(id, user);
        } on EmailSendException catch (e) {
          lastOtpError = e.message;
          rethrow;
        }
        return;
      }

      final doc = await FirebaseFirestore.instance.collection('users').doc(id).get();
      if (!doc.exists) {
        throw Exception('User not found');
      }

      final userData = doc.data()!;
      final user = AppUser(
        id: doc.id,
        fullName: userData['fullName'] as String,
        email: userData['email'] as String,
        phone: userData['phone'] as String,
        role: _parseUserRole(userData['role'] as String),
        status: userData['status'] as String,
        dateRegistered: (userData['dateRegistered'] as Timestamp).toDate(),
        password: userData['password'] as String,
      );

      lastOtpError = null;
      try {
        await _generateAndSendOtp(user);
      } on EmailSendException catch (e) {
        lastOtpError = e.message;
        rethrow;
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Permanently discards an unverified registration. This is intentionally
  /// limited to the pending collection so an already verified account can
  /// never be removed by the OTP cancellation flow.
  Future<void> discardPendingRegistration(String id) async {
    final pendingRef = FirebaseFirestore.instance
        .collection('pendingRegistrations')
        .doc(id);
    final pendingDoc = await pendingRef.get();
    if (pendingDoc.exists) {
      await pendingRef.delete();
    }
  }

  Future<String?> verifyOtp(String id, String code) async {
    try {
      final pendingDoc = await FirebaseFirestore.instance
          .collection('pendingRegistrations')
          .doc(id)
          .get();

      if (pendingDoc.exists) {
        final data = pendingDoc.data()!;
        final otpCode = data['otpCode'] as String?;
        final otpExpiry = (data['otpExpiry'] as Timestamp?)?.toDate();

        if (otpCode == null || otpExpiry == null) {
          return 'No active code. Please request a new one.';
        }

        if (DateTime.now().isAfter(otpExpiry)) {
          return 'This code has expired. Please resend a new one.';
        }

        if (code != otpCode) {
          return 'Incorrect OTP. Please try again.';
        }

        // Create the actual user document in 'users' collection with Active status
        await FirebaseFirestore.instance.collection('users').doc(id).set({
          'firstName': data['firstName'] ?? '',
          'lastName': data['lastName'] ?? '',
          'fullName': data['fullName'] ?? '',
          'email': (data['email'] as String? ?? '').toLowerCase(),
          'phone': data['phone'] ?? '',
          'role': data['role'] ?? 'customer',
          'dateRegistered': FieldValue.serverTimestamp(),
          'password': data['password'] ?? '',
          'status': 'Active',
        });

        if (data['role'] == 'employee') {
          await FirebaseFirestore.instance.collection('employees').doc(id).set({
            'name': data['fullName'] ?? '',
            'position': 'Staff',
            'dailyRate': 300.0,
            'daysWorked': 0.0,
            'bonus': 0.0,
            'deductions': 0.0,
            'status': 'Pending',
          });
        }

        // Delete from pendingRegistrations
        await FirebaseFirestore.instance.collection('pendingRegistrations').doc(id).delete();
        notifyListeners();
        return null;
      }

      final doc = await FirebaseFirestore.instance.collection('users').doc(id).get();
      if (!doc.exists) {
        return 'User not found.';
      }

      final userData = doc.data()!;
      final otpCode = userData['otpCode'] as String?;
      final otpExpiry = (userData['otpExpiry'] as Timestamp?)?.toDate();

      if (otpCode == null || otpExpiry == null) {
        return 'No active code. Please request a new one.';
      }

      if (DateTime.now().isAfter(otpExpiry)) {
        return 'This code has expired. Please resend a new one.';
      }

      if (code != otpCode) {
        return 'Incorrect OTP. Please try again.';
      }

      await FirebaseFirestore.instance.collection('users').doc(id).update({
        'status': 'Active',
        'otpCode': FieldValue.delete(),
        'otpExpiry': FieldValue.delete(),
      });

      if (currentUser?.id == id) {
        currentUser!.status = 'Active';
        currentUser!.otpCode = null;
        currentUser!.otpExpiry = null;
        notifyListeners();
      }

      return null;
    } catch (e) {
      return 'Error verifying OTP: $e';
    }
  }

  // ===================== NOTIFICATIONS =====================
  Future<void> pushNotification(String title, String body, String type) async {
    await FirebaseFirestore.instance.collection('notifications').add({
      'title': title,
      'body': body,
      'type': type,
      'time': FieldValue.serverTimestamp(),
      'read': false,
    });
    notifyListeners();
  }

  /// Lets an employee manually flag a menu item to Admin from Menu/Kiosk
  /// Management (separate from the automatic low-stock alerts raised by
  /// [deductInventoryForSale]). Purely a notification — it never touches
  /// [updateProductStock] or any other stock management logic.
  Future<void> notifyAdminAboutProduct(Product product, {required bool restockNeeded}) async {
    final title = restockNeeded ? 'RESTOCK NEEDED' : 'LOW STOCK ALERT';
    final reportedBy = currentUser?.fullName;
    final body = '${product.name} (${product.category}) — current stock: '
        '${product.stockQuantity} / ${Product.maxStockQuantity}.'
        '${reportedBy != null ? ' Reported by $reportedBy.' : ''}';
    await pushNotification(title, body, 'Inventory');
  }

  Future<void> markAllNotificationsRead() async {
    final query = await FirebaseFirestore.instance
        .collection('notifications')
        .where('read', isEqualTo: false)
        .get();
    for (final doc in query.docs) {
      await doc.reference.update({'read': true});
    }
    notifyListeners();
  }

  // ===================== INVENTORY / POS =====================
  Future<InventoryItem?> _findInventory(String productName) async {
    try {
      final query = await FirebaseFirestore.instance
          .collection('inventory')
          .where('productName', isEqualTo: productName)
          .limit(1)
          .get();

      if (query.docs.isEmpty) return null;

      final doc = query.docs.first;
      final data = doc.data();
      return InventoryItem(
        id: doc.id,
        productName: data['productName'] as String,
        quantity: data['quantity'] as int,
        unit: data['unit'] as String,
        minimumStock: data['minimumStock'] as int,
        expiration: (data['expiration'] as Timestamp?)?.toDate(),
      );
    } catch (_) {
      return null;
    }
  }

  /// Deducts stock for each cart item and raises low-stock alerts as needed.
  Future<void> deductInventoryForSale(List<CartItem> items, {String orderType = 'Dine In'}) async {
    try {
      Future<void> deductByName(String name, int deductQty) async {
        if (deductQty <= 0) return;
        final cleanName = name.trim().toLowerCase();
        if (cleanName.isEmpty) return;

        try {
          int currentQuantity = 0;
          int minStock = 5;
          String unit = 'pcs';
          String matchedName = name;

          final invMatch = inventory.where((i) => i.productName.trim().toLowerCase() == cleanName).toList();
          if (invMatch.isNotEmpty) {
            final inv = invMatch.first;
            currentQuantity = inv.quantity;
            minStock = inv.minimumStock;
            unit = inv.unit;
            matchedName = inv.productName;
          } else {
            final invQuery = await FirebaseFirestore.instance.collection('inventory').get();
            DocumentSnapshot<Map<String, dynamic>>? foundDoc;
            for (final doc in invQuery.docs) {
              final pName = (doc.data()['productName'] as String? ?? '').trim().toLowerCase();
              if (pName == cleanName) {
                foundDoc = doc;
                break;
              }
            }

            if (foundDoc != null) {
              final data = foundDoc.data() ?? {};
              currentQuantity = (data['quantity'] as num?)?.toInt() ?? 0;
              minStock = (data['minimumStock'] as num?)?.toInt() ?? 5;
              unit = (data['unit'] as String?) ?? 'pcs';
              matchedName = (data['productName'] as String?) ?? name;
            } else {
              debugPrint('No inventory item found for "$name"');
              return;
            }
          }

          final newQuantity = (currentQuantity - deductQty).clamp(0, 1 << 30);
          final diff = newQuantity - currentQuantity;

          // Update local memory inventory
          for (final inv in inventory) {
            if (inv.productName.trim().toLowerCase() == cleanName) {
              inv.quantity = newQuantity;
            }
          }

          // Update Firestore inventory safely by querying matching document
          try {
            final q = await FirebaseFirestore.instance.collection('inventory').get();
            for (final doc in q.docs) {
              final pName = (doc.data()['productName'] as String? ?? '').trim().toLowerCase();
              if (pName == cleanName) {
                await doc.reference.update({'quantity': newQuantity});
              }
            }
          } catch (e) {
            debugPrint('Error updating inventory in Firestore for $name: $e');
          }

          // Reflect change in procurement records safely
          try {
            final procMatch = procurement.where((p) => p.productName.trim().toLowerCase() == cleanName).toList();
            if (procMatch.isNotEmpty) {
              final latestProc = procMatch.last;
              final newProcQty = (latestProc.quantity + diff).clamp(0, 1 << 30);
              latestProc.quantity = newProcQty;
            }

            final procQuery = await FirebaseFirestore.instance.collection('procurement').get();
            for (final doc in procQuery.docs) {
              final pName = (doc.data()['productName'] as String? ?? '').trim().toLowerCase();
              if (pName == cleanName) {
                final currentProcQty = (doc.data()['quantity'] as num?)?.toInt() ?? 0;
                final newProcQty = (currentProcQty + diff).clamp(0, 1 << 30);
                await doc.reference.update({'quantity': newProcQty});
              }
            }
          } catch (e) {
            debugPrint('Error updating procurement for $name: $e');
          }

          // Check low stock notification
          if (newQuantity <= minStock) {
            pushNotification(
                'LOW STOCK',
                '$matchedName is running low ($newQuantity $unit left).',
                'Inventory');
          }
        } catch (e) {
          debugPrint('Error in deductByName for "$name": $e');
        }
      }

      for (final item in items) {
        final pName = item.product.name.toLowerCase();
        final addOnNames = item.selectedAddOns.map((a) => a.name.toLowerCase()).toList();
        final addOnProcNames = item.selectedAddOns
            .expand((a) => a.procurementItems)
            .map((p) => p.toLowerCase())
            .toList();

        final bool isHotOrder = pName.contains('hot') ||
            addOnNames.any((n) => n.contains('hot')) ||
            addOnProcNames.any((p) => p.contains('hot'));

        final bool isIcedOrder = pName.contains('iced') ||
            pName.contains('cold') ||
            addOnNames.any((n) => n.contains('iced') || n.contains('cold')) ||
            addOnProcNames.any((p) => p.contains('iced') || p.contains('cold'));

        final setDeductedProcNames = <String>{};

        // 1. Deduct for main product
        if (item.product.procurementItems.isNotEmpty) {
          for (final procName in item.product.procurementItems) {
            final lowerProc = procName.toLowerCase();
            if (lowerProc.contains('drink plastic') || lowerProc.contains('solo drink') || lowerProc.contains('double drink') || lowerProc.contains('plastic bag')) {
              continue;
            }
            // If it's a hot order, skip iced items
            if (isHotOrder && !isIcedOrder && (lowerProc.contains('iced') || lowerProc.contains('cold') || lowerProc.contains('straw'))) {
              continue;
            }
            // If it's an iced order, skip hot items
            if (isIcedOrder && !isHotOrder && (lowerProc.contains('hot') || lowerProc.contains('stirrer'))) {
              continue;
            }
            await deductByName(procName, item.quantity);
            setDeductedProcNames.add(lowerProc);
          }
        } else {
          await deductByName(item.product.name, item.quantity);
        }

        // 2. Deduct for selected add-ons / flavors
        for (final addOn in item.selectedAddOns) {
          final addonTotalQty = item.quantity * (addOn.quantity <= 0 ? 1 : addOn.quantity);

          // Resolve procurement items dynamically if empty
          List<String> effectiveProcItems = List.from(addOn.procurementItems);
          if (effectiveProcItems.isEmpty) {
            final gMatch = globalAddOns.where((g) => g.name.trim().toLowerCase() == addOn.name.trim().toLowerCase()).toList();
            if (gMatch.isNotEmpty) {
              effectiveProcItems = List.from(gMatch.first.procurementItems);
            } else {
              final pMatch = item.product.addOns.where((a) => a.name.trim().toLowerCase() == addOn.name.trim().toLowerCase()).toList();
              if (pMatch.isNotEmpty) {
                effectiveProcItems = List.from(pMatch.first.procurementItems);
              }
            }
          }

          if (effectiveProcItems.isNotEmpty) {
            for (final procName in effectiveProcItems) {
              final lowerProc = procName.toLowerCase();
              if (lowerProc.contains('drink plastic') || lowerProc.contains('solo drink') || lowerProc.contains('double drink') || lowerProc.contains('plastic bag')) {
                continue;
              }
              if (isHotOrder && !isIcedOrder && (lowerProc.contains('iced') || lowerProc.contains('cold') || lowerProc.contains('straw'))) {
                continue;
              }
              if (isIcedOrder && !isHotOrder && (lowerProc.contains('hot') || lowerProc.contains('stirrer'))) {
                continue;
              }
              if (setDeductedProcNames.contains(lowerProc)) {
                continue;
              }
              await deductByName(procName, addonTotalQty);
              setDeductedProcNames.add(lowerProc);
            }
          } else {
            final lowerName = addOn.name.toLowerCase();
            if (lowerName.contains('drink plastic') || lowerName.contains('solo drink') || lowerName.contains('double drink') || lowerName.contains('plastic bag')) {
              continue;
            }
            if (isHotOrder && !isIcedOrder && (lowerName.contains('iced') || lowerName.contains('cold') || lowerName.contains('straw'))) {
              continue;
            }
            if (isIcedOrder && !isHotOrder && (lowerName.contains('hot') || lowerName.contains('stirrer'))) {
              continue;
            }
            await deductByName(addOn.name, addonTotalQty);
          }
        }
      }

      // 3. Take Out Packaging Logic (Drink Plastics, Cutlery, Cups, Covers, Boxes, Sauce Cups)
      if (orderType.toLowerCase().contains('take out')) {
        int totalDrinks = items.fold(0, (acc, item) => acc + item.quantity);
        if (totalDrinks > 0) {
          int numDoubles = totalDrinks ~/ 2;
          int numSolos = totalDrinks % 2;
          if (numDoubles > 0) {
            await deductByName('Double Drink Plastic', numDoubles);
          }
          if (numSolos > 0) {
            await deductByName('Solo Drink Plastic', numSolos);
          }
        }

        for (final item in items) {
          final name = item.product.name.toLowerCase();
          final qty = item.quantity;

          if (name.contains('cheesy bacon') || name.contains('cheesy hungarian') || name.contains('cheesy chicken poppers')) {
            await deductByName('Plastic Spoon', qty);
            await deductByName('Take Out Cup Big', qty);
            await deductByName('Take Out Cover Big', qty);
          } else if (name.contains('mini cheesy shanghai') || name.contains('mini chicken poppers')) {
            await deductByName('Plastic Spoon', qty);
            await deductByName('Take Out Cup Small', qty);
            await deductByName('Take Out Cover Small', qty);
          } else if (name.contains('chicken popper bites') || name.contains('popper bites')) {
            await deductByName('Take Out Cup Small', qty);
            await deductByName('Take Out Cover Small', qty);
            await deductByName('Sauce Cup', qty);
          } else if (name.contains('fries')) {
            await deductByName('Fries Take Out Box', qty);
            await deductByName('Sauce Cup', qty);
          }
        }
      }

      notifyListeners();
    } catch (e, stackTrace) {
      debugPrint('Error in deductInventoryForSale: $e\n$stackTrace');
    }
  }

  Future<TransactionRecord> checkout(
      {required List<CartItem> items,
      required double discount,
      required String cashier,
      String? customerId,
      String? customerName,
      String? paymentMethod,
      String? orderNumber,
      double? verifiedTotal,
      String orderType = 'Dine In',
      // Receipt generated for this sale (kiosk orders only) — stored on
      // the transaction so it stays linked to the order after completion.
      Map<String, dynamic>? receipt,
      // Skip when the caller already deducted stock for these items
      // elsewhere (e.g. a kiosk order deducts it when it first enters
      // 'Preparing', so completing it must not deduct a second time).
      bool deductStock = true}) async {
    final subtotal = items.fold(0.0, (s, i) => s + i.subtotal);
    final total = verifiedTotal ?? (subtotal - discount).clamp(0, double.infinity).toDouble();
    final resolvedOrderNumber =
        (orderNumber != null && orderNumber.isNotEmpty) ? orderNumber : _generateOrderNumber();
    final txDoc =
        await FirebaseFirestore.instance.collection('transactions').add({
      'items': items
          .map((item) => {
                'productId': item.product.id,
                'productName': item.product.name,
                'quantity': item.quantity,
                'unitPrice': item.product.price,
                'addOns': item.selectedAddOns.map((a) => a.toMap()).toList(),
                'subtotal': item.subtotal,
              })
          .toList(),
      'subtotal': subtotal,
      'discount': discount,
      'total': total,
      'timestamp': FieldValue.serverTimestamp(),
      'cashier': cashier,
      'customerId': customerId,
      'customerName': customerName,
      if (paymentMethod != null) 'paymentMethod': paymentMethod,
      'orderNumber': resolvedOrderNumber,
      if (receipt != null) 'receipt': receipt,
    });

    if (deductStock) {
      await deductInventoryForSale(items, orderType: orderType);
      await _deductProductStockForSale(items);
    }
    notifyListeners();

    return TransactionRecord(
      id: txDoc.id,
      items: items,
      subtotal: subtotal,
      discount: discount,
      total: total,
      timestamp: DateTime
          .now(), // Using local time for immediate return, Firestore has server timestamp
      cashier: cashier,
      customerId: customerId,
      customerName: customerName,
      paymentMethod: paymentMethod,
      orderNumber: resolvedOrderNumber,
    );
  }

  // ===================== KIOSK ORDERS =====================

  /// Generates a short, human-friendly reference (e.g. "ORD-4821-73") for
  /// "Pay at Counter" orders. Not guaranteed globally unique in a
  /// mathematical sense, but collision odds are negligible for a single
  /// café's daily order volume, which is all this mock backend needs.
  String _generateOrderNumber() {
    final now = DateTime.now();
    final shiftStart = DateTime(now.year, now.month, now.day, 19, 0);
    final baseDate = now.isBefore(shiftStart) ? now.subtract(const Duration(days: 1)) : now;
    final mmdd = '${baseDate.month.toString().padLeft(2, '0')}${baseDate.day.toString().padLeft(2, '0')}';

    int count = 1;
    for (final o in kioskOrders) {
      if (o.orderNumber?.startsWith('OC-$mmdd-') == true) {
        count++;
      }
    }
    return 'OC-$mmdd-${count.toString().padLeft(3, '0')}';
  }

  /// Places an order for either payment method — used by both the
  /// Customer Kiosk (`source: 'Kiosk'`, the default) and the Employee POS
  /// (`source: 'POS'`), which reuses this exact method so both entry
  /// points share identical order-creation and stock-deduction logic.
  ///
  /// - 'Pay at Counter': a unique [OrderRecord.orderNumber] is generated
  ///   automatically; the customer shows it to staff to confirm and pay.
  /// - 'GCash': [proofOfPaymentBase64] must be supplied (the customer's
  ///   uploaded screenshot/photo of their payment).
  ///
  /// [customerId]/[customerName] default to the signed-in user only for
  /// 'Kiosk' orders (a logged-in customer placing their own order). POS
  /// orders are placed by an employee on a customer's behalf, so they are
  /// never auto-attributed to the employee's own account unless the
  /// caller explicitly passes a value.
  Future<OrderRecord> placeKioskOrder(
    List<CartItem> items, {
    String? customerName,
    String paymentMethod = 'Cash',
    String? proofOfPaymentBase64,
    String source = 'Kiosk',
    String? customerId,
    String orderType = 'Dine In',
    double? extractedAmount,
    String? extractedReferenceId,
    String? extractedDateTime,
    double? partialAmountPaid,
    String? initialStatus,
    bool isGuest = false,
    String? tableNumber,
  }) async {
    if (source == 'Kiosk' && !isWithinOrderingWindow()) {
      throw Exception('Ordering is only allowed during cafe operating hours (7:00 PM to 2:00 AM).');
    }
    final orderNumber = _generateOrderNumber();
    final resolvedCustomerId =
        customerId ?? (source == 'Kiosk' ? currentUser?.id : null);
    final resolvedCustomerName =
        customerName ?? (source == 'Kiosk' ? currentUser?.fullName : null);

    final status = initialStatus ?? 'Pending';
    final isPreparing = status == 'Preparing';

    // Enforce maximum of 3 active simultaneous orders per customer
    final activeOrdersCount = kioskOrders.where((o) {
      final isCustomer = (resolvedCustomerId != null && o.customerId == resolvedCustomerId) ||
          (resolvedCustomerId == null && resolvedCustomerName != null && o.customerName == resolvedCustomerName);
      final isActiveStatus = o.status == 'Pending' || o.status == 'Preparing' || o.status == 'Ready';
      return isCustomer && isActiveStatus;
    }).length;

    if (activeOrdersCount >= 3) {
      throw Exception('Maximum limit of 3 active orders reached for this customer. Please wait for current orders to complete.');
    }

    final expiresAt = source == 'Kiosk'
        ? DateTime.now().add(const Duration(minutes: 20))
        : null;

    double cartSubtotal = 0.0;
    for (final item in items) {
      cartSubtotal += item.subtotal;
    }

    if (isPreparing) {
      await deductInventoryForSale(items, orderType: orderType);
      await _deductProductStockForSale(items);
    }

    final orderMap = <String, dynamic>{
      'items': items
          .map((item) => {
                'productId': item.product.id,
                'productName': item.product.name,
                'quantity': item.quantity,
                'unitPrice': item.product.price,
                'addOns': item.selectedAddOns.map((a) => a.toMap()).toList(),
                'subtotal': item.subtotal,
              })
          .toList(),
      'source': source,
      'createdAt': FieldValue.serverTimestamp(),
      'customerId': resolvedCustomerId,
      'customerName': resolvedCustomerName,
      'status': status,
      'discount': 0.0,
      'paymentMethod': paymentMethod,
      'orderNumber': orderNumber,
      'proofOfPaymentBase64': proofOfPaymentBase64,
      'extractedAmount': extractedAmount,
      'extractedReferenceId': extractedReferenceId,
      'extractedDateTime': extractedDateTime,
      'partialAmountPaid': partialAmountPaid,
      'verifiedTotal': isPreparing ? (extractedAmount ?? cartSubtotal) : null,
      'stockDeducted': isPreparing,
      'expiresAt': expiresAt == null ? null : Timestamp.fromDate(expiresAt),
      'orderType': orderType,
      'isGuest': isGuest,
      'tableNumber': tableNumber,
    };

    final orderDoc =
        await FirebaseFirestore.instance.collection('kioskOrders').add(orderMap);

    await pushNotification(
        'NEW ORDER',
        paymentMethod == 'GCash' || paymentMethod == 'Split Payment' || paymentMethod.contains('Partial')
            ? 'A new $orderType order ($paymentMethod) needs proof-of-payment review.'
            : 'A new $orderType order has been received.',
        'POS');

    final createdOrder = OrderRecord(
      id: orderDoc.id,
      items: items,
      source: source,
      status: status,
      createdAt: DateTime.now(), // Local time for immediate return
      customerName: resolvedCustomerName,
      customerId: resolvedCustomerId,
      paymentMethod: paymentMethod,
      orderNumber: orderNumber,
      proofOfPaymentBase64: proofOfPaymentBase64,
      extractedAmount: extractedAmount,
      extractedReferenceId: extractedReferenceId,
      extractedDateTime: extractedDateTime,
      partialAmountPaid: partialAmountPaid,
      expiresAt: expiresAt,
      orderType: orderType,
      isGuest: isGuest,
      tableNumber: tableNumber,
    );

    // Synchronously insert into local memory and notify listeners for 0-latency UI update
    kioskOrders.removeWhere((o) => o.id == createdOrder.id);
    kioskOrders.insert(0, createdOrder);
    notifyListeners();

    return createdOrder;
  }

  /// Reconstructs the CartItem list from a kioskOrders document's stored
  /// line items — shared by [updateKioskOrderStage] (deducting stock when
  /// an order first enters 'Preparing') and [completeKioskOrder] (building
  /// the final transaction).
  List<CartItem> _cartItemsFromKioskOrderData(Map<String, dynamic> orderData) {
    final rawItems = (orderData['items'] as List<dynamic>?) ?? [];
    final items = <CartItem>[];
    for (final raw in rawItems) {
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw);
      final productId = map['productId'] as String? ?? '';
      final productName = map['productName'] as String? ?? '';
      final qty = (map['quantity'] as num?)?.toInt() ?? 1;

      Product? product;
      for (final p in products) {
        if (p.id == productId || (productId.isEmpty && p.name == productName)) {
          product = p;
          break;
        }
      }
      product ??= Product(
        id: productId,
        name: productName,
        category: 'Unknown',
        price: (map['unitPrice'] as num?)?.toDouble() ?? 0.0,
      );
      items.add(CartItem(
        product: product,
        quantity: qty,
        selectedAddOns: _parseAddOns(map['addOns']),
      ));
    }
    return items;
  }

  /// Saves the (possibly edited) [receipt] onto the one kiosk order it was
  /// generated for, so the customer's own Order Card picks it up through
  /// the live `kioskOrders` listener. Only that order's document is
  /// written. Before writing, the receipt's order ID and customer ID are
  /// checked against the stored order, and the identifying fields are
  /// forced to the order's own values — a receipt can never be attached to
  /// a different order or customer.
  Future<void> saveKioskOrderReceipt(String orderId, ReceiptRecord receipt) async {
    final ref = FirebaseFirestore.instance.collection('kioskOrders').doc(orderId);
    final snap = await ref.get();
    if (!snap.exists) {
      throw Exception('Order no longer exists.');
    }
    final stored = snap.data()!;
    final storedCustomerId = stored['customerId'] as String?;
    if (receipt.orderId != orderId ||
        (receipt.customerId ?? '') != (storedCustomerId ?? '')) {
      throw Exception('Receipt does not match this order/customer.');
    }
    final map = receipt.toMap()
      ..['orderId'] = orderId
      ..['customerId'] = storedCustomerId
      ..['orderNumber'] =
          (stored['orderNumber'] as String?) ?? receipt.orderNumber
      ..['updatedAt'] = DateTime.now().toIso8601String();
    await ref.update({'receipt': map, 'receiptId': receipt.receiptId});
    notifyListeners();
  }

  /// Advances an accepted order one step through the employee-side Order
  /// Status Workflow. [stage] is 'Preparing' or 'Ready' — the two
  /// in-progress steps between 'Pending' and finalization via
  /// [completeKioskOrder]. The order stays in [kioskOrders] (still visible
  /// to the employee, and to the customer as in-progress) until it's
  /// completed.
  ///
  /// Stock is deducted here — the moment an order first enters
  /// 'Preparing' — exactly once per order. Moving on to 'Ready' (or later
  /// to 'Orders Complete') never deducts stock again; a `stockDeducted`
  /// flag on the order document is the guard against a double deduction.
  Future<void> updateKioskOrderStage(String orderId, String stage) async {
    final orderRef =
        FirebaseFirestore.instance.collection('kioskOrders').doc(orderId);

    if (stage == 'Preparing') {
      final orderDoc = await orderRef.get();
      if (!orderDoc.exists) return;
      final orderData = orderDoc.data()!;
      if (orderData['stockDeducted'] != true) {
        final items = _cartItemsFromKioskOrderData(orderData);
        final kioskOrderType = orderData['orderType'] as String? ?? 'Dine In';
        await deductInventoryForSale(items, orderType: kioskOrderType);
        await _deductProductStockForSale(items);
        await orderRef.update({'status': stage, 'stockDeducted': true});
        notifyListeners();
        return;
      }
    }

    await orderRef.update({'status': stage});
    notifyListeners();
  }

  /// Finalizes an order: creates the [TransactionRecord] the customer's
  /// "Complete Orders" list is built from, then removes it from the kiosk
  /// queue. Stock was already deducted when the order first entered
  /// 'Preparing' (see [updateKioskOrderStage]), so this step does not
  /// touch inventory again — it only makes the sale official and lets the
  /// order show up as completed. Called when the employee selects "Orders
  /// Complete" as the last step of the Order Status Workflow, not when
  /// the order is first accepted, so the order is never shown as
  /// completed before that final step.
  Future<void> completeKioskOrder(String orderId,
      {required String cashier}) async {
    final orderDoc = await FirebaseFirestore.instance
        .collection('kioskOrders')
        .doc(orderId)
        .get();
    if (!orderDoc.exists) return;
    final orderData = orderDoc.data()!;
    final items = _cartItemsFromKioskOrderData(orderData);

    final discount = (orderData['discount'] as num?)?.toDouble() ?? 0;
    final verifiedTotal = (orderData['verifiedTotal'] as num?)?.toDouble();
    await checkout(
      items: items,
      discount: discount,
      cashier: cashier,
      customerId: orderData['customerId'] as String?,
      customerName: orderData['customerName'] as String?,
      paymentMethod: orderData['paymentMethod'] as String?,
      orderNumber: orderData['orderNumber'] as String?,
      verifiedTotal: verifiedTotal,
      receipt: orderData['receipt'] is Map
          ? Map<String, dynamic>.from(orderData['receipt'] as Map)
          : null,
      // Already deducted when this order entered 'Preparing' — deducting
      // again here would double-count the sale against stock.
      deductStock: false,
    );
    await FirebaseFirestore.instance
        .collection('kioskOrders')
        .doc(orderId)
        .delete();
    notifyListeners();
  }

  /// Declines a pending order. The order is kept (not deleted) with its
  /// status flipped to 'Declined' and [reason] attached so the customer can
  /// see why on "My Orders"; the customer later dismisses it themselves via
  /// [dismissKioskOrder].
  Future<void> declineKioskOrder(String orderId, {required String reason}) async {
    await FirebaseFirestore.instance
        .collection('kioskOrders')
        .doc(orderId)
        .update({
      'status': 'Declined',
      'declineReason': reason,
    });
    notifyListeners();
  }

  /// Cancels a pending order placed by a customer.
  Future<void> cancelKioskOrder(String orderId, {required String reason}) async {
    await FirebaseFirestore.instance
        .collection('kioskOrders')
        .doc(orderId)
        .update({
      'status': 'Cancelled',
      'declineReason': 'Cancelled by customer: $reason',
    });
    notifyListeners();
  }

  /// Removes a declined order from view once the customer has acknowledged it.
  Future<void> dismissKioskOrder(String orderId) async {
    await FirebaseFirestore.instance
        .collection('kioskOrders')
        .doc(orderId)
        .delete();
    notifyListeners();
  }

  /// Records the payment method the employee selected for a kiosk order
  /// (Cash, GCash, or Multi Payment) from the Kiosk Management preview flow.
  /// Purely additive: it only updates the order's `paymentMethod` field and
  /// leaves every other behavior untouched.
  Future<void> setKioskOrderPaymentMethod(
      String orderId, String paymentMethod) async {
    await FirebaseFirestore.instance
        .collection('kioskOrders')
        .doc(orderId)
        .update({'paymentMethod': paymentMethod});
    notifyListeners();
  }

  Future<void> recordAdditionalPayment(String orderId, double amount) async {
    final ref = FirebaseFirestore.instance.collection('kioskOrders').doc(orderId);
    final doc = await ref.get();
    if (!doc.exists) return;
    final currentAdditional = (doc.data()?['additionalPaymentsPaid'] as num?)?.toDouble() ?? 0.0;
    final newAdditional = currentAdditional + amount;
    await ref.update({'additionalPaymentsPaid': newAdditional});
    notifyListeners();
  }

  /// Expires a customer Kiosk order once its 20-minute Order ID countdown has
  /// lapsed, so it drops out of the employee's Pending Orders at the same
  /// moment the customer-side card disappears. Only a still-'Pending' order is
  /// affected \u2014 an order the employee has already accepted (moved to
  /// 'Preparing'/'Ready') is left running untouched.
  Future<void> expireKioskOrder(String orderId) async {
    try {
      final ref =
          FirebaseFirestore.instance.collection('kioskOrders').doc(orderId);
      final snap = await ref.get();
      if (!snap.exists) return;
      final status = (snap.data()?['status'] as String?) ?? 'Pending';
      if (status != 'Pending') return;
      await ref.update({'status': 'Expired'});
      notifyListeners();
    } catch (e) {
      debugPrint('expireKioskOrder error: $e');
    }
  }

  /// Safety net for orders whose customer never reported the countdown
  /// finishing (e.g. the app was closed first): any still-'Pending' order
  /// whose stored [OrderRecord.expiresAt] has passed is expired. Called
  /// periodically by [_startExpirySweep].
  Future<void> purgeExpiredKioskOrders() async {
    final now = DateTime.now();
    final stale = kioskOrders
        .where((o) =>
            o.status == 'Pending' &&
            o.expiresAt != null &&
            o.expiresAt!.isBefore(now))
        .map((o) => o.id)
        .toList();
    for (final id in stale) {
      await expireKioskOrder(id);
    }
  }

  /// Starts the periodic expiry sweep once. The sweep keeps the employee's
  /// Pending Orders in sync with the customer countdown even when the
  /// customer's app is no longer in the foreground.
  void _startExpirySweep() {
    _expirySweep ??= Timer.periodic(const Duration(seconds: 20), (_) {
      purgeExpiredKioskOrders();
    });
  }

  // ===================== PAYROLL =====================
  List<Employee> get activeEmployees {
    final activeNames = users
        .where((u) => u.role == UserRole.employee && u.status == 'Active')
        .map((u) => u.fullName.toLowerCase())
        .toSet();
    return employees.where((e) => activeNames.contains(e.name.toLowerCase())).toList();
  }

  double get totalPayrollExpense {
    double total = 0.0;
    for (final e in activeEmployees) {
      total += e.netSalary;
    }
    return total;
  }

  Future<double> getTotalPayrollExpense() async => totalPayrollExpense;

  Future<void> markPayrollPaid(String employeeId) async {
    final idx = employees.indexWhere((e) => e.id == employeeId);
    if (idx == -1) return;
    final emp = employees[idx];

    // Snapshot the amount actually being paid out before resetting it.
    final netSalaryPaid = emp.netSalary;
    final now = DateTime.now();

    try {
      if (netSalaryPaid != 0) {
        await FirebaseFirestore.instance.collection('payrollHistory').add({
          'employeeId': employeeId,
          'employeeName': emp.name,
          'position': emp.position,
          'netSalary': netSalaryPaid,
          'status': 'Paid',
          'date': FieldValue.serverTimestamp(),
        });
      }

      // Paying out closes this cycle: days worked, bonus and deductions
      // all go back to 0 — status stays 'Paid' (showing the checkmark) as
      // confirmation, until the employee's next time-in starts a fresh
      // cycle and flips it back to 'Pending'. The daily rate is a
      // standing setting, so it's left untouched.
      emp.daysWorked = 0;
      emp.bonus = 0;
      emp.deductions = 0;
      emp.status = 'Paid';
      emp.lastPaidAt = now;
      notifyListeners();

      await FirebaseFirestore.instance.collection('employees').doc(employeeId).set({
        'daysWorked': 0.0,
        'bonus': 0.0,
        'deductions': 0.0,
        'status': 'Paid',
        'lastPaidAt': Timestamp.fromDate(now),
      }, SetOptions(merge: true));

      await pushNotification(
          'PAYROLL', 'Payroll for ${emp.name} is ready for viewing.', 'Payroll');
    } catch (e) {
      debugPrint('Error marking payroll paid: $e');
    }
  }

  Future<void> updateEmployeePayroll(String id,
      {double? bonus, double? deductions, double? dailyRate}) async {
    final idx = employees.indexWhere((e) => e.id == id);
    if (idx != -1) {
      final emp = employees[idx];
      if (bonus != null) emp.bonus = bonus;
      if (deductions != null) emp.deductions = deductions;
      if (dailyRate != null) emp.dailyRate = dailyRate;
      notifyListeners();
    }

    try {
      final docRef = FirebaseFirestore.instance.collection('employees').doc(id);
      await docRef.set({
        if (bonus != null) 'bonus': bonus,
        if (deductions != null) 'deductions': deductions,
        if (dailyRate != null) 'dailyRate': dailyRate,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error updating employee payroll: $e');
    }
  }

  /// The calendar dates (shift-start dates) this employee has attendance
  /// for during the current, not-yet-paid payroll cycle — i.e. since
  /// [Employee.lastPaidAt] (or their entire history if never paid). Used to
  /// show a read-only "days worked" calendar instead of a free-typed
  /// number, since daysWorked is now derived from actual time-ins.
  List<DateTime> attendanceDaysForCurrentCycle(Employee employee) {
    final cutoff = employee.lastPaidAt;
    final days = <DateTime>{};
    for (final a in attendance) {
      if (a.employeeName != employee.name) continue;
      if (cutoff != null) {
        final checkTime = a.createdAt ?? a.date;
        if (checkTime.isBefore(cutoff) || checkTime.isAtSameMomentAs(cutoff)) {
          continue;
        }
      }
      days.add(DateTime(a.date.year, a.date.month, a.date.day));
    }
    final list = days.toList()..sort();
    return list;
  }

  // ===================== ATTENDANCE =====================
  // The cafe runs one overnight shift: 6:30 PM through 2:30 AM the next
  // calendar day. Every attendance rule below is anchored to that window
  // rather than to a plain calendar date, since the shift crosses
  // midnight:
  //  - Time In is only accepted from 6:30 PM to 2:30 AM.
  //  - Timing in after 6:41 PM (an 11-minute grace period) marks 'Late',
  //    and every full 2 minutes late costs 1 peso off that day's pay.
  //  - Time Out is a normal second scan any time the shift is still open;
  //    if the employee never scans out, the shift is auto-closed at 2:30 AM.
  static const int _shiftStartHour = 18;
  static const int _shiftStartMinute = 30; // 6:30 PM
  static const int _graceMinutes = 11; // grace period -> late cutoff 6:41 PM
  static const int _shiftLengthHours = 8; // 6:30 PM -> 2:30 AM

  /// The start, late-cutoff (6:41 PM), and end (2:30 AM next day) instants
  /// of the shift that begins on [shiftDate] (a date with time zeroed).
  ({DateTime start, DateTime lateCutoff, DateTime end}) _shiftTimesFor(
      DateTime shiftDate) {
    final start = DateTime(shiftDate.year, shiftDate.month, shiftDate.day,
        _shiftStartHour, _shiftStartMinute);
    return (
      start: start,
      lateCutoff: start.add(const Duration(minutes: _graceMinutes)),
      end: start.add(const Duration(hours: _shiftLengthHours)),
    );
  }

  ({DateTime start, DateTime lateCutoff, DateTime end}) getShiftTimes(
          DateTime shiftDate) =>
      _shiftTimesFor(shiftDate);

  /// The shift-start date (time zeroed) that [moment] falls inside — i.e.
  /// the calendar day of the 6:30 PM that began the shift covering
  /// [moment], whether [moment] is that same evening or the small hours of
  /// the next morning before 2:30 AM. Returns null if [moment] falls
  /// outside cafe hours entirely (any time from 2:30 AM to 6:30 PM).
  DateTime? _shiftDateContaining(DateTime moment) {
    final today = DateTime(moment.year, moment.month, moment.day);
    for (final candidate in [today.subtract(const Duration(days: 1)), today]) {
      final t = _shiftTimesFor(candidate);
      if (!moment.isBefore(t.start) && moment.isBefore(t.end)) return candidate;
    }
    return null;
  }

  /// The shift (identified by its start date) currently in progress, or
  /// null if the cafe is closed right now. Exposed so screens can show/hide
  /// the Time In control without needing to know the shift math.
  DateTime? currentShiftDate([DateTime? at]) =>
      _shiftDateContaining(at ?? DateTime.now());

  /// True if an employee is allowed to time in right now (cafe operating
  /// hours: 6:30 PM to 2:30 AM).
  bool isWithinAttendanceWindow([DateTime? at]) =>
      currentShiftDate(at) != null;

  bool? orderingOverride; // null = follow schedule, true = force open, false = force closed

  Timer? _storeHoursTimer;

  /// True if ordering is allowed right now (cafe ordering hours: 7:00 PM to 2:00 AM, or overridden by admin).
  bool isWithinOrderingWindow([DateTime? at]) {
    if (orderingOverride != null) return orderingOverride!;

    final moment = at ?? DateTime.now();
    final today = DateTime(moment.year, moment.month, moment.day);
    for (final candidate in [today.subtract(const Duration(days: 1)), today]) {
      final start = DateTime(candidate.year, candidate.month, candidate.day, 19, 0); // 7:00 PM
      final end = DateTime(candidate.year, candidate.month, candidate.day + 1, 2, 0); // 2:00 AM next day
      if (!moment.isBefore(start) && moment.isBefore(end)) {
        return true;
      }
    }
    return false;
  }

  Future<void> _loadStoreConfig() async {
    if (!_storeConfigListenerSet) {
      _storeConfigListenerSet = true;
      _storeHoursTimer?.cancel();
      _storeHoursTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        if (orderingOverride == null) {
          notifyListeners();
        }
      });

      FirebaseFirestore.instance
          .collection('storeConfig')
          .doc('settings')
          .snapshots()
          .listen((doc) {
        if (doc.exists) {
          final data = doc.data();
          if (data != null) {
            if (data.containsKey('orderingOverride')) {
              final val = data['orderingOverride'];
              if (val == null) {
                orderingOverride = null;
              } else if (val is bool) {
                orderingOverride = val;
              }
            }
            if (data.containsKey('gcashAccountName')) {
              gcashAccountName = data['gcashAccountName'] as String? ?? 'Overnight Cafe';
              PaymentConfig.gcashAccountName = gcashAccountName;
            }
            if (data.containsKey('gcashAccountNumber')) {
              gcashAccountNumber = data['gcashAccountNumber'] as String? ?? '0917 123 4567';
              PaymentConfig.gcashAccountNumber = gcashAccountNumber;
            }
            if (data.containsKey('gcashQrBase64')) {
              gcashQrBase64 = data['gcashQrBase64'] as String?;
              PaymentConfig.gcashQrBase64 = gcashQrBase64;
            }
            if (data.containsKey('receiptTitle')) {
              receiptTitle = data['receiptTitle'] as String? ?? 'OVERNIGHT CAFE';
            }
            if (data.containsKey('receiptSubtitle')) {
              receiptSubtitle = data['receiptSubtitle'] as String? ?? 'Brgy. Calumpang, Liliw, Laguna';
            }
            if (data.containsKey('receiptFooter')) {
              receiptFooter = data['receiptFooter'] as String? ?? 'Thank you for your order!';
            }
            if (data.containsKey('selectedPrinterName')) {
              selectedPrinterName = data['selectedPrinterName'] as String? ?? '';
            }
            if (data.containsKey('selectedPrinterAddress')) {
              selectedPrinterAddress = data['selectedPrinterAddress'] as String? ?? '';
            }
            if (data.containsKey('isPrinterConnected')) {
              isPrinterConnected = data['isPrinterConnected'] as bool? ?? false;
            }
            if (data.containsKey('paperSize')) {
              paperSize = data['paperSize'] as String? ?? '80mm';
            }
            if (data.containsKey('autoPrintReceipt')) {
              autoPrintReceipt = data['autoPrintReceipt'] as bool? ?? true;
            }
            if (data.containsKey('printCopies')) {
              printCopies = data['printCopies'] as int? ?? 1;
            }
            notifyListeners();
          }
        }
      });
    }
  }

  Future<void> setOrderingOverride(bool? override) async {
    orderingOverride = override;
    notifyListeners();
    try {
      await FirebaseFirestore.instance
          .collection('storeConfig')
          .doc('settings')
          .set({'orderingOverride': override}, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error updating store ordering override in Firestore: $e');
    }
  }

  Future<void> updateGcashSettings({
    String? name,
    String? number,
    String? qrBase64,
  }) async {
    final finalName = name ?? gcashAccountName;
    final finalNumber = number ?? gcashAccountNumber;
    gcashAccountName = finalName;
    gcashAccountNumber = finalNumber;
    gcashQrBase64 = qrBase64;
    PaymentConfig.gcashAccountName = finalName;
    PaymentConfig.gcashAccountNumber = finalNumber;
    PaymentConfig.gcashQrBase64 = qrBase64;
    notifyListeners();

    try {
      await FirebaseFirestore.instance
          .collection('storeConfig')
          .doc('settings')
          .set({
        'gcashAccountName': finalName,
        'gcashAccountNumber': finalNumber,
        'gcashQrBase64': qrBase64,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error updating GCash settings in Firestore: $e');
    }
  }

  Future<void> updateReceiptSettings({
    required String title,
    required String subtitle,
    required String footer,
  }) async {
    receiptTitle = title;
    receiptSubtitle = subtitle;
    receiptFooter = footer;
    notifyListeners();

    try {
      await FirebaseFirestore.instance
          .collection('storeConfig')
          .doc('settings')
          .set({
        'receiptTitle': title,
        'receiptSubtitle': subtitle,
        'receiptFooter': footer,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error updating receipt settings in Firestore: $e');
    }
  }

  Future<void> updatePrinterSettings({
    required String printerName,
    required String printerAddress,
    required bool isConnected,
    required String paperSize,
    required bool autoPrintReceipt,
    required int printCopies,
  }) async {
    selectedPrinterName = printerName;
    selectedPrinterAddress = printerAddress;
    isPrinterConnected = isConnected;
    this.paperSize = paperSize;
    this.autoPrintReceipt = autoPrintReceipt;
    this.printCopies = printCopies;
    notifyListeners();

    try {
      await FirebaseFirestore.instance
          .collection('storeConfig')
          .doc('settings')
          .set({
        'selectedPrinterName': printerName,
        'selectedPrinterAddress': printerAddress,
        'isPrinterConnected': isConnected,
        'paperSize': paperSize,
        'autoPrintReceipt': autoPrintReceipt,
        'printCopies': printCopies,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error updating printer settings in Firestore: $e');
    }
  }

  /// The employee's currently open shift (timed in, not yet timed out), if
  /// any. Not tied to today's calendar date — an employee who timed in at
  /// 11 PM is still "open" after midnight, until they scan out or the
  /// 2:30 AM auto-close sweep closes it for them.
  AttendanceRecord? openAttendanceFor(String employeeName) {
    for (final a in attendance) {
      if (a.employeeName == employeeName && !a.hasTimedOut) return a;
    }
    return null;
  }

  /// The employee's attendance record for the shift currently in progress
  /// (matched by shift date, not raw calendar date), whether it's still
  /// open or already timed out. Null if they haven't scanned at all for
  /// tonight's shift, or if the cafe isn't currently open.
  AttendanceRecord? attendanceForCurrentShift(String employeeName) {
    final shiftDate = currentShiftDate();
    if (shiftDate == null) return null;
    for (final a in attendance) {
      if (a.employeeName == employeeName &&
          a.date.year == shiftDate.year &&
          a.date.month == shiftDate.month &&
          a.date.day == shiftDate.day) {
        return a;
      }
    }
    return null;
  }

  String _formatTimeOfDay(TimeOfDay t) =>
      '${t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod}:${t.minute.toString().padLeft(2, '0')} ${t.period == DayPeriod.am ? 'AM' : 'PM'}';

  /// Force-closes any attendance record still open past its shift's 2:30 AM
  /// cutoff (the employee forgot to scan out, or left without scanning).
  /// Called by [_attendanceSweep] every minute so it self-heals even while
  /// nobody has the app open, and defensively at the top of
  /// [recordAttendance] in case the sweep hasn't run yet.
  Future<void> autoCloseOverdueAttendance() async {
    final now = DateTime.now();
    const closeLabel = '2:30 AM';
    for (final a in attendance) {
      if (a.hasTimedOut) continue;
      final shiftEnd =
          _shiftTimesFor(DateTime(a.date.year, a.date.month, a.date.day)).end;
      if (!now.isBefore(shiftEnd)) {
        a.timeOut = closeLabel;
        if (a.id.isNotEmpty) {
          try {
            await FirebaseFirestore.instance
                .collection('attendance')
                .doc(a.id)
                .update({'timeOut': closeLabel, 'autoTimedOut': true});
          } catch (e) {
            debugPrint('Error auto-closing attendance ${a.id}: $e');
          }
        }
      }
    }
  }

  /// Starts the periodic auto-close sweep once. Mirrors [_startExpirySweep]
  /// for kiosk orders — keeps attendance accurate even when the employee
  /// who forgot to scan out never opens the app again that night.
  void _startAttendanceSweep() {
    _attendanceSweep ??= Timer.periodic(const Duration(minutes: 1), (_) {
      autoCloseOverdueAttendance();
    });
  }

  /// A scan records Time In the first time an employee scans during a
  /// shift, and automatically records Time Out the next time they scan
  /// before that shift closes. Time In is only accepted while the cafe is
  /// open (6:30 PM–2:30 AM); scanning outside that window throws. Returns
  /// the updated/created record.
  Future<AttendanceRecord> recordAttendance(String employeeName,
      {String method = 'RFID'}) async {
    final now = DateTime.now();
    final label = _formatTimeOfDay(TimeOfDay.now());

    // Close out anything overdue first, in case the sweep hasn't ticked
    // yet, so we don't mistake a stale open record for tonight's shift.
    await autoCloseOverdueAttendance();

    final openRecord = openAttendanceFor(employeeName);

    if (openRecord != null) {
      // Check if current time is within 2:00 AM to 2:30 AM window
      final shiftDate = DateTime(openRecord.date.year, openRecord.date.month, openRecord.date.day);
      final shiftTimes = _shiftTimesFor(shiftDate);
      final timeoutStart = shiftTimes.end.subtract(const Duration(minutes: 30)); // 2:00 AM

      if (now.isBefore(timeoutStart)) {
        throw Exception('Time out is only allowed from 2:00 AM to 2:30 AM.');
      }

      // A shift is open -> this scan is a Time Out.
      openRecord.timeOut = label;
      if (openRecord.id.isNotEmpty) {
        try {
          await FirebaseFirestore.instance
              .collection('attendance')
              .doc(openRecord.id)
              .update({'timeOut': label});
        } catch (e) {
          debugPrint('Error recording time-out: $e');
        }
      }
      notifyListeners();
      return openRecord;
    }

    // No shift open -> this scan wants to Time In, only allowed while the
    // cafe is actually operating (6:30 PM to 2:30 AM).
    final shiftDate = currentShiftDate(now);
    if (shiftDate == null) {
      throw Exception(
          'Time in is only allowed during cafe hours, 6:30 PM to 2:30 AM.');
    }

    final shiftTimes = _shiftTimesFor(shiftDate);
    final minutesLate = now.difference(shiftTimes.lateCutoff).inMinutes;
    final isLate = minutesLate > 0;
    final status = isLate ? 'Late' : 'Present';
    // Every full 2 minutes late costs the employee 1 peso off that day's pay.
    final lateDeduction = isLate ? (minutesLate ~/ 2).toDouble() : 0.0;

    final record = AttendanceRecord(
      employeeName: employeeName,
      date: shiftDate,
      createdAt: now,
      timeIn: label,
      status: status,
      method: method,
    );

    final doc = await FirebaseFirestore.instance.collection('attendance').add({
      'employeeName': employeeName,
      'date': Timestamp.fromDate(shiftDate),
      'createdAt': FieldValue.serverTimestamp(),
      'timeIn': label,
      'timeOut': null,
      'status': status,
      'method': method,
    });
    record.id = doc.id;

    // Timing in only ever changes two things in payroll: the employee's
    // daysWorked always goes up by 1, and, only when they're late, their
    // deductions go up by 1 peso per 2 minutes late.
    final empIdx = employees.indexWhere(
        (e) => e.name.toLowerCase() == employeeName.toLowerCase() || e.id == employeeName);
    if (empIdx != -1) {
      final emp = employees[empIdx];
      emp.daysWorked = attendanceDaysForCurrentCycle(emp).length.toDouble();
      if (lateDeduction > 0) emp.deductions += lateDeduction;
      // A new time-in after payout starts a fresh cycle — flip the badge
      // back to 'Pending' so it doesn't keep showing last cycle's Paid
      // checkmark for salary that hasn't actually been paid out yet.
      final startsNewCycle = emp.status == 'Paid';
      if (startsNewCycle) emp.status = 'Pending';
      try {
        await FirebaseFirestore.instance.collection('employees').doc(emp.id).set({
          'daysWorked': emp.daysWorked,
          if (lateDeduction > 0) 'deductions': emp.deductions,
          if (startsNewCycle) 'status': 'Pending',
        }, SetOptions(merge: true));
      } catch (e) {
        debugPrint('Error updating employee days worked: $e');
      }
    }

    notifyListeners();
    return record;
  }

  Future<void> deleteAttendanceRecord(String recordId) async {
    final idx = attendance.indexWhere((a) => a.id == recordId);
    if (idx == -1) return;
    final record = attendance[idx];
    attendance.removeAt(idx);
    notifyListeners();

    try {
      await FirebaseFirestore.instance.collection('attendance').doc(recordId).delete();

      final empIdx = employees.indexWhere(
          (e) => e.name.toLowerCase() == record.employeeName.toLowerCase());
      if (empIdx != -1) {
        final emp = employees[empIdx];
        emp.daysWorked = attendanceDaysForCurrentCycle(emp).length.toDouble();
        await FirebaseFirestore.instance.collection('employees').doc(emp.id).set({
          'daysWorked': emp.daysWorked,
        }, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint('Error deleting attendance record: $e');
    }
  }

  // ===================== FEEDBACK =====================
  /// [orderId] (a completed order/transaction ID) and [customerId] link the
  /// feedback to a specific customer's specific order. When [orderId] is
  /// given, a duplicate submission for the same order is rejected — each
  /// completed order allows only one feedback.
  Future<FeedbackRecord> submitFeedback(
      {required String customerName,
      required int rating,
      required String comment,
      required String category,
      String? customerId,
      String? orderId}) async {
    if (orderId != null && hasFeedbackForOrder(orderId)) {
      throw StateError('Feedback has already been submitted for this order.');
    }

    final fbDoc = await FirebaseFirestore.instance.collection('feedbacks').add({
      'customerName': customerName,
      'rating': rating,
      'comment': comment,
      'category': category,
      'date': FieldValue.serverTimestamp(),
      'status': 'New',
      if (customerId != null) 'customerId': customerId,
      if (orderId != null) 'orderId': orderId,
    });

    await pushNotification('NEW FEEDBACK',
        'A customer submitted a $rating-star review.', 'Feedback');

    final fbSnapshot = await fbDoc.get();
    final fbData = fbSnapshot.data()!;

    return FeedbackRecord(
      id: fbDoc.id,
      customerName: fbData['customerName'] as String,
      rating: fbData['rating'] as int,
      comment: fbData['comment'] as String,
      category: fbData['category'] as String,
      date: DateTime.now(), // Local time for immediate return
      status: 'New',
      customerId: customerId,
      orderId: orderId,
    );
  }

  Future<void> markFeedbackReviewed(String id, {String? reply}) async {
    try {
      await FirebaseFirestore.instance.collection('feedbacks').doc(id).update({
        'status': 'Reviewed',
        if (reply != null) 'reply': reply,
      });
      notifyListeners();
    } catch (e) {
      // In a real app, you might want to log this error
      rethrow;
    }
  }

  // ===================== PETTY CASH =====================
  final Map<String, double> pettyCashDailyStarts = {};
  double _defaultPettyCashStart = 5000.0;

  String pettyCashShiftKey(DateTime moment) {
    final shiftStart = DateTime(moment.year, moment.month, moment.day, 18, 30);
    DateTime baseDate;
    if (moment.isBefore(shiftStart)) {
      baseDate = moment.subtract(const Duration(days: 1));
    } else {
      baseDate = moment;
    }
    return '${baseDate.year.toString().padLeft(4, '0')}-${baseDate.month.toString().padLeft(2, '0')}-${baseDate.day.toString().padLeft(2, '0')}';
  }

  double pettyCashStartFor([DateTime? date]) =>
      pettyCashDailyStarts[pettyCashShiftKey(date ?? DateTime.now())] ?? _defaultPettyCashStart;

  double get pettyCashStart => pettyCashStartFor();

  Future<void> updatePettyCashStart(double newStart) async {
    final value = newStart.clamp(0.0, double.infinity).toDouble();
    final currentShiftKey = pettyCashShiftKey(DateTime.now());
    pettyCashDailyStarts[currentShiftKey] = value;
    notifyListeners();
    try {
      await FirebaseFirestore.instance.collection('pettyCashConfig').doc('settings').set({
        'startingBalance': value,
        'dailyStartingBalances': pettyCashDailyStarts,
        'date': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error updating petty cash start: $e');
    }
  }

  double get pettyCashExpenses {
    double total = 0.0;
    final currentShiftKey = pettyCashShiftKey(DateTime.now());
    for (final e in pettyCash) {
      if (pettyCashShiftKey(e.date) == currentShiftKey && e.amount < 0) {
        total += e.amount.abs();
      }
    }
    return total;
  }

  double get pettyCashAdded {
    double total = 0.0;
    final currentShiftKey = pettyCashShiftKey(DateTime.now());
    for (final e in pettyCash) {
      if (pettyCashShiftKey(e.date) == currentShiftKey && e.amount > 0) {
        total += e.amount;
      }
    }
    return total;
  }

  double get pettyCashBalance => pettyCashStart + pettyCashAdded - pettyCashExpenses;

  Future<void> addPettyCash(
      String description, String category, double amount) async {
    await FirebaseFirestore.instance.collection('pettyCash').add({
      'description': description,
      'category': category,
      'amount': amount,
      'date': FieldValue.serverTimestamp(),
    });
    notifyListeners();
  }

  Future<void> archivePettyCash(String id, {String archivedBy = 'Admin'}) async {
    try {
      final doc = await FirebaseFirestore.instance.collection('pettyCash').doc(id).get();
      if (!doc.exists) return;
      final data = doc.data()!;

      await FirebaseFirestore.instance.collection('archive').add({
        'category': 'Expenses',
        'name': data['description'] ?? '',
        'email': data['category'] ?? '',
        'role': '₱${(data['amount'] as num? ?? 0).toStringAsFixed(2)}',
        'dateArchived': FieldValue.serverTimestamp(),
        'archivedBy': archivedBy,
        'rawPettyCashData': data,
        'originalRecordId': id,
      });

      await FirebaseFirestore.instance.collection('pettyCash').doc(id).delete();
      pettyCash.removeWhere((p) => p.id == id);
      notifyListeners();
    } catch (e) {
      debugPrint('Error archiving petty cash: $e');
    }
  }

  Future<void> archivePayroll(String id, {String archivedBy = 'Admin'}) async {
    try {
      final doc = await FirebaseFirestore.instance.collection('payrollHistory').doc(id).get();
      if (!doc.exists) return;
      final data = doc.data()!;

      await FirebaseFirestore.instance.collection('archive').add({
        'category': 'Payroll',
        'name': data['employeeName'] ?? '',
        'email': data['position'] ?? '',
        'role': '₱${(data['netSalary'] as num? ?? 0).toStringAsFixed(2)}',
        'dateArchived': FieldValue.serverTimestamp(),
        'archivedBy': archivedBy,
        'rawPayrollData': data,
        'originalRecordId': id,
      });

      await FirebaseFirestore.instance.collection('payrollHistory').doc(id).delete();
      payrollHistory.removeWhere((p) => p.id == id);
      notifyListeners();
    } catch (e) {
      debugPrint('Error archiving payroll: $e');
    }
  }

  Future<void> archiveTransaction(String id, {String archivedBy = 'Admin'}) async {
    try {
      final doc = await FirebaseFirestore.instance.collection('transactions').doc(id).get();
      if (!doc.exists) return;
      final data = doc.data()!;
      final total = (data['total'] as num? ?? 0).toStringAsFixed(2);
      final ts = (data['timestamp'] as Timestamp?)?.toDate();
      final dateLabel = ts != null ? '${ts.month}/${ts.day}/${ts.year}' : '';

      await FirebaseFirestore.instance.collection('archive').add({
        'category': 'Sales',
        'name': 'Sale — $dateLabel',
        'email': data['cashier'] ?? '',
        'role': '₱$total',
        'dateArchived': FieldValue.serverTimestamp(),
        'archivedBy': archivedBy,
        'rawTransactionData': data,
        'originalRecordId': id,
      });

      await FirebaseFirestore.instance.collection('transactions').doc(id).update({
        'archivedByAdmin': true,
      });

      final idx = transactions.indexWhere((t) => t.id == id);
      if (idx != -1) {
        final existing = transactions[idx];
        transactions[idx] = TransactionRecord(
          id: existing.id,
          items: existing.items,
          subtotal: existing.subtotal,
          discount: existing.discount,
          total: existing.total,
          timestamp: existing.timestamp,
          cashier: existing.cashier,
          customerId: existing.customerId,
          customerName: existing.customerName,
          paymentMethod: existing.paymentMethod,
          orderNumber: existing.orderNumber,
          orderType: existing.orderType,
          receipt: existing.receipt,
          archivedByAdmin: true,
        );
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Error archiving transaction: $e');
    }
  }

  Future<void> archiveCustomerOrder(String id, String displayId, String details, String status, {String archivedBy = 'Customer', String? originalCustomerId}) async {
    try {
      Map<String, dynamic>? rawOrderData;
      final kioskDoc = await FirebaseFirestore.instance.collection('kioskOrders').doc(id).get();
      if (kioskDoc.exists) {
        rawOrderData = kioskDoc.data();
        await FirebaseFirestore.instance.collection('kioskOrders').doc(id).delete();
        kioskOrders.removeWhere((o) => o.id == id);
      } else {
        final txDoc = await FirebaseFirestore.instance.collection('transactions').doc(id).get();
        if (txDoc.exists) {
          rawOrderData = txDoc.data();
          await FirebaseFirestore.instance.collection('transactions').doc(id).delete();
          transactions.removeWhere((t) => t.id == id);
        }
      }

      await FirebaseFirestore.instance.collection('archive').add({
        'category': 'Customer Orders',
        'name': 'Order #$displayId',
        'email': details,
        'role': status,
        'dateArchived': FieldValue.serverTimestamp(),
        'archivedBy': archivedBy,
        'originalCustomerId': originalCustomerId,
        'rawOrderData': rawOrderData,
      });
      notifyListeners();
    } catch (e) {
      debugPrint('Error archiving customer order: $e');
    }
  }

  Future<void> archiveFeedback(String feedbackId, {String archivedBy = 'Employee'}) async {
    try {
      final doc = await FirebaseFirestore.instance.collection('feedbacks').doc(feedbackId).get();
      if (!doc.exists) return;
      final data = doc.data()!;
      await FirebaseFirestore.instance.collection('archive').add({
        'category': 'Customer Feedback',
        'name': 'Feedback from ${data['customerName'] ?? 'Customer'}',
        'email': '${data['rating'] ?? 5} stars: ${data['comment'] ?? ''}',
        'role': data['reviewed'] == true ? 'Reviewed' : 'Pending',
        'dateArchived': FieldValue.serverTimestamp(),
        'archivedBy': archivedBy,
        'rawFeedbackData': data,
        'originalRecordId': feedbackId,
      });

      await FirebaseFirestore.instance.collection('feedbacks').doc(feedbackId).delete();
      feedbacks.removeWhere((f) => f.id == feedbackId);
      notifyListeners();
    } catch (e) {
      debugPrint('Error archiving feedback: $e');
    }
  }

  // ===================== PROCUREMENT =====================
  Future<void> addProcurement(
      String productName, String supplier, int quantity, double cost,
      {String itemType = 'Inventory Item', DateTime? expiration}) async {
    final cleanName = productName.trim();
    if (cleanName.isEmpty) return;

    final existingProcMatch = procurement.where(
      (p) => p.productName.trim().toLowerCase() == cleanName.toLowerCase() && p.itemType == itemType
    ).toList();

    if (existingProcMatch.isNotEmpty) {
      // Update existing procurement record without creating a duplicate row!
      final existing = existingProcMatch.last;
      String resolvedSupplier = supplier.trim();
      if (resolvedSupplier.isEmpty) {
        resolvedSupplier = existing.supplier; // Retain existing supplier name
      }
      final newQty = existing.quantity + quantity;
      final resolvedCost = cost > 0 ? cost : existing.cost; // Retain existing cost if not entered

      await FirebaseFirestore.instance.collection('procurement').doc(existing.id).update({
        'productName': cleanName,
        'supplier': resolvedSupplier,
        'quantity': newQty,
        'cost': resolvedCost,
        'date': FieldValue.serverTimestamp(),
        'status': 'Restocked',
        'itemType': itemType,
        if (expiration != null) 'expiration': Timestamp.fromDate(expiration),
      });
    } else {
      // Create first procurement record
      String resolvedSupplier = supplier.trim().isEmpty ? 'Local Supplier' : supplier.trim();
      await FirebaseFirestore.instance.collection('procurement').add({
        'productName': cleanName,
        'supplier': resolvedSupplier,
        'quantity': quantity,
        'cost': cost,
        'date': FieldValue.serverTimestamp(),
        'status': 'Restocked',
        'itemType': itemType,
        'expiration': expiration != null ? Timestamp.fromDate(expiration) : null,
      });
    }

    // Update or create inventory item
    final inv = await _findInventory(cleanName);
    if (inv != null) {
      final newQty = inv.quantity + quantity;
      final updates = <String, dynamic>{
        'productName': cleanName,
        'quantity': newQty,
        'itemType': itemType,
        if (expiration != null) 'expiration': Timestamp.fromDate(expiration),
      };
      await FirebaseFirestore.instance
          .collection('inventory')
          .doc(inv.id)
          .update(updates);
    } else {
      await FirebaseFirestore.instance.collection('inventory').add({
        'productName': cleanName,
        'quantity': quantity,
        'unit': 'pcs',
        'minimumStock': 5,
        'itemType': itemType,
        'expiration': expiration != null ? Timestamp.fromDate(expiration) : null,
      });
    }
    notifyListeners();
  }

  Future<void> updateProcurement(
      String id, String productName, String supplier, int quantity, double cost,
      {String itemType = 'Inventory Item', DateTime? expiration}) async {
    await FirebaseFirestore.instance.collection('procurement').doc(id).update({
      'productName': productName,
      'supplier': supplier,
      'quantity': quantity,
      'cost': cost,
      'itemType': itemType,
      'expiration': expiration != null ? Timestamp.fromDate(expiration) : null,
    });

    final inv = await _findInventory(productName);
    if (inv != null) {
      final updates = <String, dynamic>{
        'productName': productName,
        'quantity': quantity,
        'itemType': itemType,
      };
      if (expiration != null) updates['expiration'] = Timestamp.fromDate(expiration);
      await FirebaseFirestore.instance.collection('inventory').doc(inv.id).update(updates);
    } else {
      await FirebaseFirestore.instance.collection('inventory').add({
        'productName': productName,
        'quantity': quantity,
        'unit': 'pcs',
        'minimumStock': 5,
        'itemType': itemType,
        'expiration': expiration != null ? Timestamp.fromDate(expiration) : null,
      });
    }
    notifyListeners();
  }

  Future<void> updateInventoryItem(
      String id, {
      required String productName,
      required int quantity,
      required String unit,
      required int minimumStock,
      String itemType = 'Inventory Item',
      DateTime? expiration,
  }) async {
    final item = inventory.firstWhere((i) => i.id == id,
        orElse: () => InventoryItem(id: id, productName: productName, quantity: quantity, unit: unit, minimumStock: minimumStock, itemType: itemType));
    item.productName = productName;
    item.quantity = quantity.clamp(0, 1 << 30);
    item.unit = unit;
    item.minimumStock = minimumStock;
    item.itemType = itemType;
    item.expiration = expiration;
    notifyListeners();

    try {
      await FirebaseFirestore.instance.collection('inventory').doc(id).update({
        'productName': productName,
        'quantity': item.quantity,
        'unit': unit,
        'minimumStock': minimumStock,
        'itemType': itemType,
        'expiration': expiration != null ? Timestamp.fromDate(expiration) : null,
      });

      final procMatch = procurement.where((p) => p.productName.toLowerCase() == productName.toLowerCase()).toList();
      if (procMatch.isNotEmpty) {
        final latestProc = procMatch.last;
        await FirebaseFirestore.instance.collection('procurement').doc(latestProc.id).update({
          'productName': productName,
          'quantity': item.quantity,
          'itemType': itemType,
          if (expiration != null) 'expiration': Timestamp.fromDate(expiration),
        });
      }
    } catch (e) {
      debugPrint('Error updating inventory item: $e');
    }
  }

  Future<void> updateInventoryQuantity(String id, int newQty) async {
    final item = inventory.firstWhere((i) => i.id == id,
        orElse: () => InventoryItem(
            id: id, productName: '', quantity: newQty, unit: 'pcs', minimumStock: 5));
    final oldQty = item.quantity;
    final diff = newQty - oldQty;
    item.quantity = newQty.clamp(0, 1 << 30);
    notifyListeners();
    try {
      await FirebaseFirestore.instance.collection('inventory').doc(id).update({
        'quantity': item.quantity,
      });

      // Reflect change in procurement records for this product name
      final procMatch = procurement.where((p) => p.productName.toLowerCase() == item.productName.toLowerCase()).toList();
      if (procMatch.isNotEmpty) {
        final latestProc = procMatch.last;
        final newProcQty = (latestProc.quantity + diff).clamp(0, 1 << 30);
        await FirebaseFirestore.instance.collection('procurement').doc(latestProc.id).update({
          'quantity': newProcQty,
        });
      }
    } catch (e) {
      debugPrint('Error updating inventory quantity: $e');
    }
  }

  Future<void> addInventoryItem({
    required String productName,
    required int quantity,
    required String unit,
    required int minimumStock,
    DateTime? expiration,
    String itemType = 'Inventory Item',
  }) async {
    try {
      await FirebaseFirestore.instance.collection('inventory').add({
        'productName': productName,
        'quantity': quantity,
        'unit': unit,
        'minimumStock': minimumStock,
        'expiration': expiration != null ? Timestamp.fromDate(expiration) : null,
        'itemType': itemType,
      });
      notifyListeners();
    } catch (e) {
      debugPrint('Error adding inventory item: $e');
      inventory.add(InventoryItem(
        id: 'I-${inventory.length + 1}',
        productName: productName,
        quantity: quantity,
        unit: unit,
        minimumStock: minimumStock,
        expiration: expiration,
        itemType: itemType,
      ));
      notifyListeners();
    }
  }

  // ===================== PROMOTIONS =====================
  Future<void> addPromotion(String productName, String promoType) async {
    await FirebaseFirestore.instance.collection('promotions').add({
      'productName': productName,
      'promoType': promoType,
      'createdAt': FieldValue.serverTimestamp(),
    });
    notifyListeners();
  }

  // ===================== USER MANAGEMENT / ARCHIVE =====================
  Future<AppUser> registerUserByAdmin({
    required String firstName,
    required String lastName,
    required String fullName,
    required String email,
    required String phone,
    required String password,
    required UserRole role,
  }) async {
    try {
      final pendingDoc = await FirebaseFirestore.instance.collection('pendingRegistrations').add({
        'firstName': firstName,
        'lastName': lastName,
        'fullName': fullName,
        'email': email.toLowerCase(),
        'phone': phone,
        'role': role.toString().split('.').last,
        'dateRegistered': FieldValue.serverTimestamp(),
        'password': password,
        'status': 'Pending Verification',
      });

      final user = AppUser(
        id: pendingDoc.id,
        fullName: fullName,
        firstName: firstName,
        lastName: lastName,
        email: email.toLowerCase(),
        phone: phone,
        role: role,
        status: 'Pending Verification',
        dateRegistered: DateTime.now(),
        password: password,
      );

      lastOtpError = null;
      try {
        await _generateAndSendOtpForPending(pendingDoc.id, user);
      } on EmailSendException catch (e) {
        lastOtpError = e.message;
      }
      return user;
    } catch (e) {
      rethrow;
    }
  }

  Future<AppUser?> findUserByEmail(String email) async {
    final cleanEmail = email.toLowerCase().trim();
    final query = await FirebaseFirestore.instance
        .collection('users')
        .where('email', isEqualTo: cleanEmail)
        .get();
    if (query.docs.isEmpty) return null;
    final doc = query.docs.first;
    final data = doc.data();
    return AppUser(
      id: doc.id,
      fullName: data['fullName'] as String? ?? 'User',
      email: data['email'] as String? ?? cleanEmail,
      phone: data['phone'] as String? ?? '',
      role: _parseUserRole(data['role'] as String? ?? 'customer'),
      status: data['status'] as String? ?? 'Active',
      dateRegistered: (data['dateRegistered'] as Timestamp?)?.toDate() ?? DateTime.now(),
      password: data['password'] as String? ?? '',
    );
  }

  Future<void> sendPasswordResetOtp(String email) async {
    final user = await findUserByEmail(email);
    if (user == null) {
      throw Exception('No account found with this email address.');
    }
    lastOtpError = null;
    try {
      await _generateAndSendOtp(user);
    } on EmailSendException catch (e) {
      lastOtpError = e.message;
      rethrow;
    }
  }

  Future<void> updatePassword(String userId, String newPassword) async {
    await FirebaseFirestore.instance.collection('users').doc(userId).update({
      'password': newPassword,
      'otpCode': FieldValue.delete(),
      'otpExpiry': FieldValue.delete(),
    });
    notifyListeners();
  }

  Future<void> updateProfile({
    required String userId,
    required String firstName,
    required String lastName,
    String? suffix,
    required String email,
    required String phone,
  }) async {
    final cleanFn = firstName.trim();
    final cleanLn = lastName.trim();
    final cleanSuf = (suffix ?? '').trim();
    final fullName = cleanSuf.isNotEmpty ? '$cleanFn $cleanLn $cleanSuf' : '$cleanFn $cleanLn';
    final cleanEmail = email.trim();
    final cleanPhone = phone.trim();

    if (currentUser != null && currentUser!.id == userId) {
      currentUser!.firstName = cleanFn;
      currentUser!.lastName = cleanLn;
      currentUser!.suffix = cleanSuf.isNotEmpty ? cleanSuf : null;
      currentUser!.fullName = fullName;
      currentUser!.email = cleanEmail;
      currentUser!.phone = cleanPhone;
    }
    final idx = users.indexWhere((u) => u.id == userId);
    if (idx != -1) {
      users[idx].firstName = cleanFn;
      users[idx].lastName = cleanLn;
      users[idx].suffix = cleanSuf.isNotEmpty ? cleanSuf : null;
      users[idx].fullName = fullName;
      users[idx].email = cleanEmail;
      users[idx].phone = cleanPhone;
    }
    await FirebaseFirestore.instance.collection('users').doc(userId).update({
      'firstName': cleanFn,
      'lastName': cleanLn,
      'suffix': cleanSuf,
      'fullName': fullName,
      'email': cleanEmail,
      'phone': cleanPhone,
    });
    notifyListeners();
  }

  Future<void> updateProfileImage(String userId, String base64Image) async {
    if (currentUser != null && currentUser!.id == userId) {
      currentUser!.profileImage = base64Image;
    }
    final idx = users.indexWhere((u) => u.id == userId);
    if (idx != -1) {
      users[idx].profileImage = base64Image;
    }
    await FirebaseFirestore.instance.collection('users').doc(userId).update({
      'profileImage': base64Image,
    });
    notifyListeners();
  }

  Future<void> sendChangePasswordOtp(AppUser user) async {
    lastOtpError = null;
    try {
      await _generateAndSendOtp(user);
    } on EmailSendException catch (e) {
      lastOtpError = e.message;
      rethrow;
    }
  }

  Future<void> sendEmailChangeOtp(AppUser user, String newEmail) async {
    lastOtpError = null;
    final otp = EmailService.instance.generateOtp();
    user.otpCode = otp;
    user.otpExpiry = DateTime.now().add(const Duration(minutes: 5));
    notifyListeners();

    try {
      await FirebaseFirestore.instance.collection('users').doc(user.id).update({
        'otpCode': otp,
        'otpExpiry': user.otpExpiry,
      });
    } catch (e) {
      throw EmailSendException('Failed to save OTP to database: $e');
    }

    try {
      await EmailService.instance.sendOtpEmail(
        toEmail: newEmail.trim(),
        toName: user.fullName,
        otp: otp,
      );
    } on EmailSendException catch (e) {
      lastOtpError = e.message;
      rethrow;
    }
  }

  Future<void> addUser(AppUser user) async {
    final userDoc = await FirebaseFirestore.instance.collection('users').add({
      'fullName': user.fullName,
      'email': user.email.toLowerCase(),
      'phone': user.phone,
      'role': user.role
          .toString()
          .split('.')
          .last, // 'admin', 'employee', or 'customer'
      'dateRegistered': FieldValue.serverTimestamp(),
      'password': user.password, // TODO: In production, hash this password!
      'status': user.status,
      'position': user.position,
      'employeeId': user.employeeId,
    });

    if (user.role == UserRole.employee) {
      await FirebaseFirestore.instance.collection('employees').doc(userDoc.id).set({
        'name': user.fullName,
        'position': user.position ?? 'Staff',
        'dailyRate': 300.0,
        'daysWorked': 0.0,
        'bonus': 0.0,
        'deductions': 0.0,
        'status': 'Pending',
      });
    }

    notifyListeners();
  }

  Future<void> updateUserStatus(String userId, String newStatus) async {
    try {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(userId).get();
      if (userDoc.exists) {
        await FirebaseFirestore.instance.collection('users').doc(userId).update({'status': newStatus});
        final idx = users.indexWhere((u) => u.id == userId);
        if (idx != -1) {
          users[idx].status = newStatus;
        }
      } else {
        final pendingDoc = await FirebaseFirestore.instance.collection('pendingRegistrations').doc(userId).get();
        if (pendingDoc.exists) {
          final data = pendingDoc.data()!;
          if (newStatus == 'Active') {
            await FirebaseFirestore.instance.collection('users').doc(userId).set({
              'firstName': data['firstName'] ?? '',
              'lastName': data['lastName'] ?? '',
              'fullName': data['fullName'] ?? '',
              'email': (data['email'] as String? ?? '').toLowerCase(),
              'phone': data['phone'] ?? '',
              'role': data['role'] ?? 'customer',
              'dateRegistered': FieldValue.serverTimestamp(),
              'password': data['password'] ?? '',
              'status': 'Active',
            });

            if (data['role'] == 'employee') {
              await FirebaseFirestore.instance.collection('employees').doc(userId).set({
                'name': data['fullName'] ?? '',
                'position': 'Staff',
                'dailyRate': 300.0,
                'daysWorked': 0.0,
                'bonus': 0.0,
                'deductions': 0.0,
                'status': 'Pending',
              });
            }

            await FirebaseFirestore.instance.collection('pendingRegistrations').doc(userId).delete();
          } else {
            await FirebaseFirestore.instance.collection('pendingRegistrations').doc(userId).update({'status': newStatus});
          }
        }
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Error updating user status: $e');
    }
  }

  Future<void> archiveUser(String userId, {String archivedBy = 'Admin'}) async {
    try {
      var userDoc =
          await FirebaseFirestore.instance.collection('users').doc(userId).get();
      Map<String, dynamic>? userData;
      bool isPending = false;

      if (userDoc.exists) {
        userData = userDoc.data()!;
      } else {
        userDoc = await FirebaseFirestore.instance.collection('pendingRegistrations').doc(userId).get();
        if (userDoc.exists) {
          userData = userDoc.data()!;
          isPending = true;
        }
      }

      if (userData == null) return;

      final fullName = userData['fullName'] as String? ?? 'User';
      final email = userData['email'] as String? ?? '';
      final roleStr = userData['role'] as String? ?? 'customer';
      final roleLabel = _parseUserRole(roleStr) == UserRole.admin
          ? 'Admin'
          : (_parseUserRole(roleStr) == UserRole.employee ? 'Employee' : 'Customer');

      await FirebaseFirestore.instance.collection('archive').add({
        'id': userId,
        'category': 'Users',
        'name': fullName,
        'email': email.toLowerCase(),
        'role': roleLabel,
        'dateArchived': FieldValue.serverTimestamp(),
        'archivedBy': archivedBy,
        'originalUserId': userId,
        'userData': userData,
      });

      if (isPending) {
        await FirebaseFirestore.instance.collection('pendingRegistrations').doc(userId).delete();
      } else {
        await FirebaseFirestore.instance.collection('users').doc(userId).delete();

        // Delete corresponding employee record
        final empQuery = await FirebaseFirestore.instance
            .collection('employees')
            .where('name', isEqualTo: fullName)
            .get();
        for (final doc in empQuery.docs) {
          await doc.reference.delete();
        }

        // Delete attendance records for this employee
        final attQuery = await FirebaseFirestore.instance
            .collection('attendance')
            .where('employeeName', isEqualTo: fullName)
            .get();
        for (final doc in attQuery.docs) {
          await doc.reference.delete();
        }
      }

      users.removeWhere((u) => u.id == userId);
      _activeUsersMap.remove(userId);
      _pendingUsersMap.remove(userId);
      notifyListeners();
    } catch (e) {
      debugPrint('Error archiving user: $e');
    }
  }

  Future<void> archiveProcurement(String id, {String archivedBy = 'Admin'}) async {
    try {
      final doc = await FirebaseFirestore.instance.collection('procurement').doc(id).get();
      if (!doc.exists) return;
      final data = doc.data()!;
      final productName = data['productName'] as String? ?? '';
      final itemType = data['itemType'] as String? ?? 'Inventory Item';
      final categoryName = itemType == 'Kitchen Item' ? 'Kitchen Items' : 'Inventory Items';

      await FirebaseFirestore.instance.collection('archive').add({
        'category': categoryName,
        'name': productName,
        'email': 'Supplier: ${data['supplier'] ?? 'Local'} | Qty: ${data['quantity']}',
        'role': 'Cost: ₱${(data['cost'] as num? ?? 0).toStringAsFixed(2)}',
        'dateArchived': FieldValue.serverTimestamp(),
        'archivedBy': archivedBy,
        'recordData': data,
        'rawProcurementData': data,
        'originalRecordId': id,
      });

      await FirebaseFirestore.instance.collection('procurement').doc(id).delete();
      procurement.removeWhere((p) => p.id == id);

      // Automatically archive/remove matching inventory items as well
      final invMatch = inventory.where((i) => i.productName.toLowerCase() == productName.toLowerCase()).toList();
      for (final invItem in invMatch) {
        try {
          await FirebaseFirestore.instance.collection('inventory').doc(invItem.id).delete();
        } catch (e) {
          debugPrint('Error deleting matching inventory doc ${invItem.id}: $e');
        }
      }
      inventory.removeWhere((i) => i.productName.toLowerCase() == productName.toLowerCase());

      notifyListeners();
    } catch (e) {
      debugPrint('Error archiving procurement: $e');
    }
  }

  Future<void> restoreRecord(ArchivedRecord record) async {
    final recordDoc = await FirebaseFirestore.instance
        .collection('archive')
        .doc(record.id)
        .get();
    if (!recordDoc.exists) {
      archive.removeWhere((a) => a.id == record.id);
      notifyListeners();
      return;
    }

    final recordData = recordDoc.data()!;
    final category = recordData['category'] as String? ?? record.category;

    if (category == 'Inventory Items' || category == 'Kitchen Items' || category == 'Inventory') {
      final itemData = recordData['rawItemData'] as Map<String, dynamic>? ?? {
        'productName': record.name,
        'quantity': 1,
        'unit': 'pcs',
        'minimumStock': 5,
        'itemType': category == 'Kitchen Items' ? 'Kitchen Item' : 'Inventory Item',
      };
      await FirebaseFirestore.instance.collection('inventory').add(itemData);
    } else if (category == 'Procurement' || category == 'Kitchen Procurement' || category == 'Inventory Procurement') {
      final procData = recordData['rawProcurementData'] as Map<String, dynamic>? ?? recordData['recordData'] as Map<String, dynamic>? ?? {
        'productName': record.name,
        'supplier': record.email,
        'quantity': 1,
        'cost': 0.0,
        'date': FieldValue.serverTimestamp(),
        'status': 'Restocked',
        'itemType': category == 'Kitchen Procurement' ? 'Kitchen Item' : 'Inventory Item',
      };
      await FirebaseFirestore.instance.collection('procurement').add(procData);
    } else if (category == 'Products') {
      final productData = recordData['productData'] as Map<String, dynamic>?;
      if (productData != null) {
        await FirebaseFirestore.instance.collection('products').add(productData);
      }
    } else if (category == 'Sales') {
      final txData = recordData['rawTransactionData'] as Map<String, dynamic>? ?? {
        'items': [],
        'subtotal': 0.0,
        'discount': 0.0,
        'total': 0.0,
        'timestamp': FieldValue.serverTimestamp(),
        'cashier': record.email,
      };
      await FirebaseFirestore.instance.collection('transactions').add(txData);
    } else if (category == 'Customer Feedback' || category == 'Feedback') {
      final fbData = recordData['rawFeedbackData'] as Map<String, dynamic>? ?? {
        'customerName': record.name.replaceFirst('Feedback from ', ''),
        'rating': 5,
        'comment': record.email,
        'reviewed': record.role == 'Reviewed',
        'date': FieldValue.serverTimestamp(),
      };
      await FirebaseFirestore.instance.collection('feedbacks').add(fbData);
    } else if (category == 'Customer Orders') {
      final rawOrderData = recordData['rawOrderData'] as Map<String, dynamic>?;
      if (rawOrderData != null) {
        if (record.role == 'Completed' || rawOrderData.containsKey('timestamp')) {
          await FirebaseFirestore.instance.collection('transactions').add(rawOrderData);
        } else {
          await FirebaseFirestore.instance.collection('kioskOrders').add(rawOrderData);
        }
      } else {
        await FirebaseFirestore.instance.collection('kioskOrders').add({
          'status': record.role,
          'createdAt': FieldValue.serverTimestamp(),
          'customerId': recordData['originalCustomerId'],
        });
      }
    } else if (category == 'Payroll' || category == 'Payroll History') {
      final payrollData = recordData['rawPayrollData'] as Map<String, dynamic>? ?? {
        'employeeName': record.name,
        'position': record.email,
        'netSalary': 0.0,
        'status': 'Paid',
        'date': FieldValue.serverTimestamp(),
      };
      await FirebaseFirestore.instance.collection('payrollHistory').add(payrollData);
    } else {
      final originalUserId = recordData['originalUserId'] as String?;
      final userData = recordData['userData'] as Map<String, dynamic>?;

      if (originalUserId != null && originalUserId.isNotEmpty) {
        if (userData != null) {
          userData['status'] = 'Active';
          await FirebaseFirestore.instance
              .collection('users')
              .doc(originalUserId)
              .set(userData, SetOptions(merge: true));

          final roleStr = userData['role'] as String? ?? 'customer';
          final fullName = userData['fullName'] as String? ?? record.name;
          final position = userData['position'] as String? ?? 'Staff';

          if (_parseUserRole(roleStr) == UserRole.employee) {
            await FirebaseFirestore.instance.collection('employees').doc(originalUserId).set({
              'name': fullName,
              'position': position,
              'dailyRate': 300.0,
              'daysWorked': 0.0,
              'bonus': 0.0,
              'deductions': 0.0,
              'status': 'Pending',
            }, SetOptions(merge: true));
          }
        } else {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(originalUserId)
              .update({'status': 'Active'});
        }
      }
    }

    await FirebaseFirestore.instance
        .collection('archive')
        .doc(record.id)
        .delete();
    archive.removeWhere((a) => a.id == record.id);
    notifyListeners();
  }

  Future<void> permanentlyDelete(String recordId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('archive')
          .doc(recordId)
          .get();
      if (doc.exists) {
        final data = doc.data()!;
        final category = data['category'] as String? ?? '';
        final name = (data['name'] as String? ?? '').trim().toLowerCase();
        final originalUserId = data['originalUserId'] as String?;

        if (category == 'Users' || category == 'Employees') {
          if (originalUserId != null && originalUserId.isNotEmpty) {
            await FirebaseFirestore.instance.collection('users').doc(originalUserId).delete();
            await FirebaseFirestore.instance.collection('employees').doc(originalUserId).delete();
          }
          if (name.isNotEmpty) {
            final empQuery = await FirebaseFirestore.instance.collection('employees').get();
            for (final eDoc in empQuery.docs) {
              if ((eDoc.data()['name'] as String? ?? '').trim().toLowerCase() == name) {
                await eDoc.reference.delete();
              }
            }
            final attQuery = await FirebaseFirestore.instance.collection('attendance').get();
            for (final aDoc in attQuery.docs) {
              if ((aDoc.data()['employeeName'] as String? ?? '').trim().toLowerCase() == name) {
                await aDoc.reference.delete();
              }
            }
          }
        }
        await doc.reference.delete();
      }
    } catch (e) {
      debugPrint('Error deleting archive doc $recordId: $e');
    }
    archive.removeWhere((a) => a.id == recordId);
    notifyListeners();
  }

  Future<void> permanentlyDeleteAll(List<ArchivedRecord> records) async {
    try {
      final idsToRemove = <String>{};
      final futures = records.map((r) async {
        idsToRemove.add(r.id);
        try {
          final doc = await FirebaseFirestore.instance
              .collection('archive')
              .doc(r.id)
              .get();
          if (doc.exists) {
            final data = doc.data()!;
            final category = data['category'] as String? ?? '';
            final name = (data['name'] as String? ?? '').trim().toLowerCase();
            final originalUserId = data['originalUserId'] as String?;

            if (category == 'Users' || category == 'Employees') {
              if (originalUserId != null && originalUserId.isNotEmpty) {
                await FirebaseFirestore.instance.collection('users').doc(originalUserId).delete();
                await FirebaseFirestore.instance.collection('employees').doc(originalUserId).delete();
              }
              if (name.isNotEmpty) {
                final empQuery = await FirebaseFirestore.instance.collection('employees').get();
                for (final eDoc in empQuery.docs) {
                  if ((eDoc.data()['name'] as String? ?? '').trim().toLowerCase() == name) {
                    await eDoc.reference.delete();
                  }
                }
                final attQuery = await FirebaseFirestore.instance.collection('attendance').get();
                for (final aDoc in attQuery.docs) {
                  if ((aDoc.data()['employeeName'] as String? ?? '').trim().toLowerCase() == name) {
                    await aDoc.reference.delete();
                  }
                }
              }
            }
            await doc.reference.delete();
          }
        } catch (e) {
          debugPrint('Error deleting archive doc ${r.id}: $e');
        }
      });

      await Future.wait(futures);
      archive.removeWhere((a) => idsToRemove.contains(a.id));
      notifyListeners();
    } catch (e) {
      debugPrint('Error in permanentlyDeleteAll: $e');
    }
  }

  // ===================== PRODUCT / MENU MANAGEMENT =====================
  Future<void> addProduct(String name, String category, double price, String description,
      {int stockQuantity = 0, List<MenuAddOn>? addOns, String? imageBase64}) async {
    final clampedStock = stockQuantity.clamp(0, Product.maxStockQuantity);
    final addOnsList = addOns ?? [];
    await FirebaseFirestore.instance.collection('products').add({
      'name': name,
      'category': category,
      'price': price,
      'description': description,
      'imageBase64': imageBase64,
      'stockQuantity': clampedStock,
      'addOns': addOnsList.map((a) => a.toMap()).toList(),
      'procurementItems': [],
    });
    notifyListeners();
  }

  Future<void> addBatchProducts(List<Map<String, dynamic>> items) async {
    for (final item in items) {
      final name = item['name'] as String;
      final category = item['category'] as String;
      final price = (item['price'] as num).toDouble();
      final stock = (item['stock'] as num).toInt();
      final clampedStock = stock.clamp(0, Product.maxStockQuantity);
      final addOns = (item['addOns'] as List<MenuAddOn>?) ?? [];
      final imageBase64 = item['imageBase64'] as String? ?? '';

      await FirebaseFirestore.instance.collection('products').add({
        'name': name,
        'category': category,
        'price': price,
        'description': '',
        'imageBase64': imageBase64,
        'stockQuantity': clampedStock,
        'addOns': addOns.map((a) => a.toMap()).toList(),
        'procurementItems': [],
      });
    }
    notifyListeners();
  }

  Future<void> updateProductProcurementItems(String productId, List<String> items) async {
    final idx = products.indexWhere((p) => p.id == productId);
    if (idx != -1) {
      products[idx].procurementItems = items;
    }
    await FirebaseFirestore.instance.collection('products').doc(productId).update({
      'procurementItems': items,
    });
    notifyListeners();
  }

  Future<void> updateProductBestSeller(String productId, bool isBestSeller) async {
    final idx = products.indexWhere((p) => p.id == productId);
    if (idx != -1) {
      products[idx].isBestSeller = isBestSeller;
    }
    await FirebaseFirestore.instance.collection('products').doc(productId).update({
      'isBestSeller': isBestSeller,
    });
    notifyListeners();
  }

  Future<void> updateProduct(String id, String name, String category, double price, String description,
      {int? stockQuantity, String? imageBase64}) async {
    final update = <String, dynamic>{
      'name': name,
      'category': category,
      'price': price,
      'description': description,
      'imageBase64': imageBase64,
    };
    if (stockQuantity != null) {
      update['stockQuantity'] = stockQuantity.clamp(0, Product.maxStockQuantity);
    }
    await FirebaseFirestore.instance.collection('products').doc(id).update(update);

    final idx = products.indexWhere((p) => p.id == id);
    if (idx != -1) {
      products[idx].name = name;
      products[idx].category = category;
      products[idx].price = price;
      products[idx].description = description;
      products[idx].imageBase64 = imageBase64;
      if (stockQuantity != null) {
        products[idx].stockQuantity = stockQuantity.clamp(0, Product.maxStockQuantity);
        await _checkProductStockAlert(products[idx]);
      }
    }
    notifyListeners();
  }



  List<MenuAddOn> globalAddOns = [];
  bool _globalAddOnsListenerSet = false;

  Future<void> _loadGlobalAddOns() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('addOnsConfig').doc('global').get();
      if (doc.exists) {
        final rawList = doc.data()?['addOns'] as List<dynamic>?;
        if (rawList != null) {
          globalAddOns = rawList.map((m) => MenuAddOn.fromMap(m as Map<String, dynamic>)).toList();
        }
      } else {
        globalAddOns = [
          MenuAddOn(name: 'Extra Shot', price: 30, category: 'Extras', allowQuantity: true),
          MenuAddOn(name: 'Oat Milk', price: 50, category: 'Extras', allowQuantity: false),
          MenuAddOn(name: 'Caramel Syrup', price: 25, category: 'Flavors', allowQuantity: false),
          MenuAddOn(name: 'Vanilla Syrup', price: 25, category: 'Flavors', allowQuantity: false),
          MenuAddOn(name: 'Pearl Sinker', price: 20, category: 'Extras', allowQuantity: true),
        ];
        await saveGlobalAddOns(globalAddOns);
      }
      if (!_globalAddOnsListenerSet) {
        _globalAddOnsListenerSet = true;
        FirebaseFirestore.instance
            .collection('addOnsConfig')
            .doc('global')
            .snapshots()
            .listen((snap) {
          final rawList = snap.data()?['addOns'] as List<dynamic>?;
          if (!snap.exists || rawList == null) return;
          globalAddOns = rawList
              .map((m) => MenuAddOn.fromMap(Map<String, dynamic>.from(m as Map)))
              .toList();
          notifyListeners();
        });
      }
    } catch (e) {
      debugPrint('Error loading global add-ons: $e');
    }
  }

  Future<void> saveGlobalAddOns(List<MenuAddOn> newAddOns) async {
    globalAddOns = newAddOns;
    try {
      await FirebaseFirestore.instance.collection('addOnsConfig').doc('global').set({
        'addOns': globalAddOns.map((a) => a.toMap()).toList(),
      });
    } catch (e) {
      debugPrint('Error saving global add-ons: $e');
    }
    notifyListeners();
  }

  Future<void> updateProductAddOns(String productId, List<MenuAddOn> addOns) async {
    final idx = products.indexWhere((p) => p.id == productId);
    if (idx != -1) {
      products[idx].addOns = addOns;
      notifyListeners();
    }
    try {
      await FirebaseFirestore.instance.collection('products').doc(productId).update({
        'addOns': addOns.map((a) => a.toMap()).toList(),
      });
    } catch (e) {
      debugPrint('Error updating product add-ons: $e');
    }
  }

  /// Directly set a menu item's stock quantity (0-200) — used for quick
  /// restock/adjust actions in Menu Management. Automatically raises a
  /// low-stock/out-of-stock alert when the new quantity crosses either
  /// threshold, and (via [Product.isAvailableForOrder]) automatically hides
  /// the item from the Kiosk and POS once it hits 0.
  Future<void> updateProductStock(String productId, int newQuantity) async {
    final clamped = newQuantity.clamp(0, Product.maxStockQuantity);
    final idx = products.indexWhere((p) => p.id == productId);
    if (idx == -1) return;

    products[idx].stockQuantity = clamped;
    notifyListeners();

    try {
      await FirebaseFirestore.instance
          .collection('products')
          .doc(productId)
          .update({'stockQuantity': clamped});
    } catch (e) {
      debugPrint('Error updating product stock: $e');
    }
    await _checkProductStockAlert(products[idx]);
  }

  /// Deducts menu-item stock for a completed sale (POS checkout or an
  /// accepted Kiosk order) and raises low-stock/out-of-stock alerts.
  Future<void> _deductProductStockForSale(List<CartItem> items) async {
    for (final item in items) {
      final idx = products.indexWhere((p) => p.id == item.product.id);
      if (idx == -1) continue;
      final product = products[idx];
      final newQty = (product.stockQuantity - item.quantity)
          .clamp(0, Product.maxStockQuantity);
      product.stockQuantity = newQty;
      try {
        await FirebaseFirestore.instance
            .collection('products')
            .doc(product.id)
            .update({'stockQuantity': newQty});
      } catch (e) {
        debugPrint('Error deducting product stock: $e');
      }
      await _checkProductStockAlert(product);
    }
  }

  /// Pushes a shared alert (visible to Admin and Employee via the
  /// notification bell) when a menu item becomes low on stock or sells out.
  Future<void> _checkProductStockAlert(Product product) async {
    if (product.isOutOfStock) {
      await pushNotification(
          'OUT OF STOCK',
          '${product.name} is out of stock and has been removed from ordering on the Kitchen and POS.',
          'Menu');
    } else if (product.isLowStock) {
      await pushNotification(
          'LOW STOCK',
          '${product.name} is running low (${product.stockQuantity} left).',
          'Menu');
    }
  }

  Future<void> archiveProduct(String id, {String archivedBy = 'Admin'}) async {
    final doc = await FirebaseFirestore.instance.collection('products').doc(id).get();
    if (!doc.exists) return;
    final data = doc.data()!;

    await FirebaseFirestore.instance.collection('archive').add({
      'category': 'Products',
      'name': data['name'] ?? '',
      'email': data['category'] ?? '',
      'role': '₱${(data['price'] as num? ?? 0).toStringAsFixed(2)}',
      'dateArchived': FieldValue.serverTimestamp(),
      'archivedBy': archivedBy,
      'productData': data,
      'originalProductId': id,
    });

    await FirebaseFirestore.instance.collection('products').doc(id).delete();
    products.removeWhere((p) => p.id == id);
    notifyListeners();
  }

  Future<void> archiveInventory(String id, {String archivedBy = 'Admin'}) async {
    final doc = await FirebaseFirestore.instance.collection('inventory').doc(id).get();
    if (!doc.exists) {
      inventory.removeWhere((i) => i.id == id);
      notifyListeners();
      return;
    }
    final data = doc.data()!;
    final productName = data['productName'] as String? ?? '';
    final itemType = data['itemType'] as String? ?? 'Inventory Item';
    final categoryName = itemType == 'Kitchen Item' ? 'Kitchen Items' : 'Inventory Items';

    await FirebaseFirestore.instance.collection('archive').add({
      'category': categoryName,
      'name': productName,
      'email': '${data['quantity']} ${data['unit']}',
      'role': 'Min: ${data['minimumStock']}',
      'dateArchived': FieldValue.serverTimestamp(),
      'archivedBy': archivedBy,
      'originalId': id,
      'rawItemData': data,
    });

    await FirebaseFirestore.instance.collection('inventory').doc(id).delete();
    inventory.removeWhere((i) => i.id == id);

    // Also remove matching procurement records from Firestore and memory
    final matchingProc = procurement.where((p) => p.productName.toLowerCase() == productName.toLowerCase()).toList();
    for (final procItem in matchingProc) {
      try {
        await FirebaseFirestore.instance.collection('procurement').doc(procItem.id).delete();
      } catch (e) {
        debugPrint('Error deleting matching procurement record ${procItem.id}: $e');
      }
    }
    procurement.removeWhere((p) => p.productName.toLowerCase() == productName.toLowerCase());

    notifyListeners();
  }
}

Uint8List compressImage(Uint8List originalBytes, {int maxDimension = 800, int quality = 75}) {
  try {
    final originalImage = img.decodeImage(originalBytes);
    if (originalImage == null) return originalBytes;

    img.Image resized = originalImage;
    if (originalImage.width > maxDimension || originalImage.height > maxDimension) {
      resized = img.copyResize(
        originalImage,
        width: originalImage.width > originalImage.height ? maxDimension : null,
        height: originalImage.height >= originalImage.width ? maxDimension : null,
      );
    }

    final compressedBytes = img.encodeJpg(resized, quality: quality);
    return Uint8List.fromList(compressedBytes);
  } catch (e) {
    debugPrint('Error compressing image: $e');
    return originalBytes;
  }
}

String formatUserFriendlyError(dynamic error) {
  final msg = error.toString().toLowerCase();
  if (msg.contains('proofofpaymentbase64') || msg.contains('longer than') || msg.contains('1048487') || msg.contains('invalid-argument')) {
    return 'The receipt image file size is too large. Please take another picture or upload a smaller image.';
  }
  if (msg.contains('network') || msg.contains('socket') || msg.contains('connection') || msg.contains('failed host lookup')) {
    return 'Network connection error. Please check your internet connection and try again.';
  }
  if (msg.contains('operating hours') || msg.contains('7:00 pm')) {
    return 'Ordering is only allowed during cafe operating hours (7:00 PM to 2:00 AM).';
  }
  if (msg.contains('maximum limit of 3 active orders')) {
    return 'This customer has reached the maximum limit of 3 active orders. Please wait for current orders to complete.';
  }
  return error.toString().replaceAll('Exception: ', '').replaceAll('[cloud_firestore/invalid-argument]', '').trim();
}

