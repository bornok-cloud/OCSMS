import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../services/app_data.dart';
import '../../widgets/shared_widgets.dart';

class CustomerFeedbackScreen extends StatefulWidget {
  const CustomerFeedbackScreen({super.key});
  @override
  State<CustomerFeedbackScreen> createState() => _CustomerFeedbackScreenState();
}

class _CustomerFeedbackScreenState extends State<CustomerFeedbackScreen> {
  int _rating = 0;
  String _category = 'Service';
  final _commentCtrl = TextEditingController();
  bool _submitted = false;

  void _submit() {
    if (_rating == 0) return;
    AppData.instance.submitFeedback(
      customerName: AppData.instance.currentUser?.fullName ?? 'Customer',
      rating: _rating,
      comment: _commentCtrl.text.trim(),
      category: _category,
    );
    setState(() => _submitted = true);
  }

  @override
  Widget build(BuildContext context) {
    return SectionPage(children: [
      Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: _submitted
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.favorite,
                            color: AppColors.accent, size: 48),
                        const SizedBox(height: 12),
                        const Text('Thank you for your feedback!',
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppColors.darkBrown)),
                        const SizedBox(height: 16),
                        OutlinedButton(
                          onPressed: () => setState(() {
                            _submitted = false;
                            _rating = 0;
                            _commentCtrl.clear();
                          }),
                          child: const Text('Submit Another'),
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('How was your experience?',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: AppColors.darkBrown)),
                        const SizedBox(height: 16),
                        Center(
                            child: StarRating(
                                rating: _rating,
                                size: 34,
                                onChanged: (r) => setState(() => _rating = r))),
                        const SizedBox(height: 18),
                        DropdownButtonFormField<String>(
                          initialValue: _category,
                          decoration:
                              const InputDecoration(labelText: 'Category'),
                          items: const [
                            'Service',
                            'Food Quality',
                            'Cleanliness',
                            'Ambiance',
                            'Other'
                          ]
                              .map((c) =>
                                  DropdownMenuItem(value: c, child: Text(c)))
                              .toList(),
                          onChanged: (v) =>
                              setState(() => _category = v ?? _category),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _commentCtrl,
                          maxLines: 4,
                          decoration: const InputDecoration(
                              hintText: 'Write your feedback...'),
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton(
                            onPressed: _submit,
                            child: const SizedBox(
                                width: double.infinity,
                                child: Text('Submit Feedback',
                                    textAlign: TextAlign.center))),
                      ],
                    ),
            ),
          ),
        ),
      ),
    ]);
  }
}
