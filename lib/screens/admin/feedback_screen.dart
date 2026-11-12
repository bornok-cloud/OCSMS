import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../services/app_data.dart';
import '../../widgets/shared_widgets.dart';
import '../../models/models.dart';

/// Shared by Admin (full access + reply) and Employee (view-only, limited access).
class FeedbackScreen extends StatefulWidget {
  final bool canReply;
  const FeedbackScreen({super.key, this.canReply = false});
  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  String _search = '';
  String _filter = 'All';

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppData.instance,
      builder: (context, _) {
        var items = AppData.instance.feedbacks
            .where((f) => f.customerName.toLowerCase().contains(_search.toLowerCase()))
            .toList();
        if (_filter != 'All') items = items.where((f) => f.status == _filter).toList();

        return SectionPage(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: 'Search customer name...',
                      prefixIcon: Icon(Icons.search),
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() => _search = v),
                  ),
                ),
                const SizedBox(width: 12),
                DropdownButton<String>(
                  value: _filter,
                  items: const ['All', 'New', 'Reviewed']
                      .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                      .toList(),
                  onChanged: (v) => setState(() => _filter = v ?? 'All'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            PaginatedList<FeedbackRecord>(
              items: items,
              pageSize: 6,
              itemBuilder: (context, f) => _CompactFeedbackCard(
                feedback: f,
                canReply: widget.canReply,
                onArchive: () async {
                  await AppData.instance.archiveFeedback(f.id);
                  if (context.mounted) {
                    showAppSnack(context, 'Feedback archived and sent to admin.');
                  }
                },
                onMarkReviewed: () => setState(() => AppData.instance.markFeedbackReviewed(f.id)),
                onReply: () => _replyDialog(context, f.id, f.customerName),
              ),
            ),
            if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('No feedback found.', style: TextStyle(color: AppColors.textMuted)),
              ),
          ],
        );
      },
    );
  }

  void _replyDialog(BuildContext context, String id, String customerName) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: AppColors.cardWhite,
        title: Text('Reply to $customerName\'s Feedback', style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.darkBrown)),
        content: TextField(
          controller: ctrl,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: 'Write your reply...',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.darkBrown,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              final replyText = ctrl.text.trim();
              if (replyText.isEmpty) {
                showAppSnack(context, 'Reply cannot be empty.', success: false);
                return;
              }
              setState(() => AppData.instance.markFeedbackReviewed(id, reply: replyText));
              Navigator.pop(ctx);
              showAppSnack(context, 'Reply sent to $customerName successfully!');
            },
            child: const Text('Send Reply'),
          ),
        ],
      ),
    );
  }
}

class _CompactFeedbackCard extends StatelessWidget {
  final FeedbackRecord feedback;
  final bool canReply;
  final VoidCallback onArchive;
  final VoidCallback onMarkReviewed;
  final VoidCallback onReply;

  const _CompactFeedbackCard({
    required this.feedback,
    required this.canReply,
    required this.onArchive,
    required this.onMarkReviewed,
    required this.onReply,
  });

  @override
  Widget build(BuildContext context) {
    final f = feedback;

    // Resolve display order number
    final tx = AppData.instance.transactions
        .where((t) => t.id == f.orderId || t.orderNumber == f.orderId)
        .firstOrNull;
    final orderNum = f.orderId != null
        ? (tx?.displayOrderNumber ??
            (f.orderId!.startsWith('ORD-')
                ? f.orderId!
                : 'ORD-${f.orderId!.substring(0, f.orderId!.length.clamp(0, 7)).toUpperCase()}'))
        : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.soft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header Row: Customer Name, Order Badge, Rating, Archive Icon
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        f.customerName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13.5,
                          color: AppColors.darkBrown,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (orderNum != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.beige,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppColors.beigeDark, width: 0.6),
                        ),
                        child: Text(
                          '#$orderNum',
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.darkBrown,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              StarRating(rating: f.rating, size: 14),
              const SizedBox(width: 6),
              InkWell(
                onTap: onArchive,
                borderRadius: BorderRadius.circular(6),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(
                    Icons.archive_outlined,
                    size: 16,
                    color: AppColors.darkBrown,
                  ),
                ),
              ),
            ],
          ),

          if (f.comment.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              f.comment.trim(),
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.darkBrown,
                height: 1.35,
              ),
            ),
          ],

          if (f.reply != null && f.reply!.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.beige,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.beigeDark, width: 0.8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.subdirectory_arrow_right_rounded,
                    size: 14,
                    color: AppColors.darkBrown,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Café reply: ${f.reply!.trim()}',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontStyle: FontStyle.italic,
                        color: AppColors.darkBrown,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 8),

          // Footer Row: Category Tag, Status Badge, Timestamp, & Actions
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.beige,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.beigeDark, width: 0.6),
                ),
                child: Text(
                  f.category,
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.darkBrown,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              StatusBadge(status: f.status),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  formatDateTime(f.date),
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
              if (canReply && f.status == 'New') ...[
                const SizedBox(width: 8),
                InkWell(
                  onTap: onMarkReviewed,
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.darkBrown, width: 0.8),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check, size: 12, color: AppColors.darkBrown),
                        SizedBox(width: 3),
                        Text(
                          'Review',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            color: AppColors.darkBrown,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                InkWell(
                  onTap: onReply,
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.darkBrown,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.reply, size: 12, color: Colors.white),
                        SizedBox(width: 3),
                        Text(
                          'Reply',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
