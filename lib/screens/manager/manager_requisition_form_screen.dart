import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../core/api/json_case.dart';
import '../../repositories/requisitions_repository.dart';
import 'manager_requisitions_screen.dart';

const _priorities = ['low', 'medium', 'high', 'urgent'];
const _employmentTypes = {
  'full_time': 'Full time',
  'part_time': 'Part time',
  'contract': 'Contract',
  'intern': 'Intern',
  'consultant': 'Consultant',
};

/// Validation that mirrors the server's rules. Each returns an error text or null.
class RequisitionRules {
  RequisitionRules._();

  static String? title(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return 'Position title is required';
    if (s.length > 200) return 'Use 200 characters or fewer';
    return null;
  }

  static String? positions(String? v) {
    final n = int.tryParse((v ?? '').trim());
    if (n == null || n < 1 || n > 500) return 'Enter a number from 1 to 500';
    return null;
  }

  static String? experience(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return null;
    final n = num.tryParse(s);
    if (n == null || n < 0 || n > 80) return 'Enter 0 to 80';
    return null;
  }

  static String? salary(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return null;
    final n = num.tryParse(s);
    if (n == null || n < 0) return 'Enter 0 or more';
    return null;
  }

  static String? currency(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return null;
    return RegExp(r'^[A-Za-z]{3}$').hasMatch(s) ? null : 'Use a 3-letter code';
  }

  /// min must not exceed max when both are given.
  static String? range(String? min, String? max, String message) {
    final a = num.tryParse((min ?? '').trim());
    final b = num.tryParse((max ?? '').trim());
    if (a != null && b != null && a > b) return message;
    return null;
  }
}

/// Create a requisition, or edit a draft / rejected one. 'Save draft' keeps it private; 'Submit for approval' sends it.
class RequisitionFormScreen extends StatefulWidget {
  const RequisitionFormScreen({
    super.key,
    required this.repository,
    this.existing,
  });

  final RequisitionsRepository repository;
  final Map<String, dynamic>? existing;

  @override
  State<RequisitionFormScreen> createState() => _RequisitionFormScreenState();
}

class _RequisitionFormScreenState extends State<RequisitionFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _department = TextEditingController();
  final _location = TextEditingController();
  final _positions = TextEditingController(text: '1');
  final _expMin = TextEditingController();
  final _expMax = TextEditingController();
  final _salMin = TextEditingController();
  final _salMax = TextEditingController();
  final _currency = TextEditingController(text: 'INR');
  final _skills = TextEditingController();
  final _quals = TextEditingController();
  final _jd = TextEditingController();
  final _justification = TextEditingController();

  String _priority = 'medium';
  String? _employmentType;
  bool _isReplacement = false;
  String? _reportingTo;
  String? _replacing;
  DateTime? _joining;
  Map<String, String> _names = const {};
  bool _saving = false;
  String? _error;

  bool get _editing => widget.existing != null;
  bool get _rejected => widget.existing?['status'] == 'rejected';

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      String s(dynamic v) => v?.toString() ?? '';
      _title.text = s(e['position_title']);
      _department.text = s(e['department']);
      _location.text = s(e['location']);
      _positions.text = '${asInt(e['number_of_positions'], 1)}';
      _expMin.text = s(e['experience_min']);
      _expMax.text = s(e['experience_max']);
      _salMin.text = s(e['salary_min']);
      _salMax.text = s(e['salary_max']);
      if (s(e['currency']).isNotEmpty) _currency.text = s(e['currency']);
      _skills.text = e['key_skills'] is List
          ? (e['key_skills'] as List).join(', ')
          : '';
      _quals.text = e['qualifications'] is List
          ? (e['qualifications'] as List).join(', ')
          : '';
      _jd.text = s(e['job_description']);
      _justification.text = s(e['business_justification']);
      if (_priorities.contains(e['priority'])) {
        _priority = e['priority'].toString();
      }
      final et = e['employment_type']?.toString();
      _employmentType = _employmentTypes.containsKey(et) ? et : null;
      _isReplacement = e['is_replacement'] == true;
      final rt = s(e['reporting_to']);
      _reportingTo = rt.isEmpty ? null : rt;
      _joining = asDate(e['expected_joining_date']);
    }
    widget.repository
        .employeeNames()
        .then((n) {
          if (!mounted) return;
          setState(() => _names = n);
        })
        .catchError((_) {});
  }

  @override
  void dispose() {
    for (final c in [
      _title,
      _department,
      _location,
      _positions,
      _expMin,
      _expMax,
      _salMin,
      _salMax,
      _currency,
      _skills,
      _quals,
      _jd,
      _justification,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  List<String> _split(String v) => v
      .split(RegExp(r'[,\n]'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  Map<String, dynamic> _body() {
    String? t(TextEditingController c) {
      final s = c.text.trim();
      return s.isEmpty ? null : s;
    }

    final body = <String, dynamic>{
      'position_title': _title.text.trim(),
      'department': t(_department),
      'location': t(_location),
      'reporting_to': _reportingTo,
      'employment_type': _employmentType,
      'number_of_positions': int.parse(_positions.text.trim()),
      'priority': _priority,
      'is_replacement': _isReplacement,
      'replacing_employee_id': _isReplacement ? _replacing : null,
      'experience_min': num.tryParse(_expMin.text.trim()),
      'experience_max': num.tryParse(_expMax.text.trim()),
      'salary_min': num.tryParse(_salMin.text.trim()),
      'salary_max': num.tryParse(_salMax.text.trim()),
      'currency': t(_currency)?.toUpperCase(),
      'key_skills': _split(_skills.text),
      'qualifications': _split(_quals.text),
      'job_description': t(_jd),
      'business_justification': t(_justification),
      'expected_joining_date': _joining == null
          ? null
          : DateFormat('yyyy-MM-dd').format(_joining!),
    };
    body.removeWhere((k, v) => v == null);
    return body;
  }

  Future<void> _save({required bool submit}) async {
    if (_saving || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final body = _body();
      if (_editing) {
        final id = widget.existing!['id'].toString();
        await widget.repository.update(id, body);
        if (submit) await widget.repository.submit(id);
      } else {
        await widget.repository.create(body, submit: submit);
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = requisitionActionError(e);
      });
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _joining ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (d != null) setState(() => _joining = d);
  }

  Widget _gap() => const SizedBox(height: 12);

  Widget _number(
    TextEditingController c,
    String label,
    String? Function(String?) v, {
    Key? key,
    bool decimal = true,
  }) => TextFormField(
    key: key,
    controller: c,
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
    ),
    keyboardType: TextInputType.numberWithOptions(decimal: decimal),
    validator: v,
  );

  Widget _text(
    TextEditingController c,
    String label, {
    Key? key,
    int lines = 1,
    String? Function(String?)? validator,
  }) => TextFormField(
    key: key,
    controller: c,
    minLines: lines,
    maxLines: lines == 1 ? 1 : 6,
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
    ),
    validator: validator,
  );

  Widget _employeeDropdown(
    String label,
    String? value,
    ValueChanged<String?> onChanged,
  ) {
    final entries = _names.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    final current = entries.any((e) => e.key == value) ? value : null;
    return DropdownButtonFormField<String?>(
      initialValue: current,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: [
        const DropdownMenuItem<String?>(value: null, child: Text('None')),
        for (final e in entries)
          DropdownMenuItem<String?>(value: e.key, child: Text(e.value)),
      ],
      onChanged: onChanged,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        title: Text(
          _editing ? 'Edit requisition' : 'New requisition',
          style: GoogleFonts.montserrat(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _text(
              _title,
              'Position title *',
              key: const Key('f_title'),
              validator: RequisitionRules.title,
            ),
            _gap(),
            _text(_department, 'Department'),
            _gap(),
            _text(_location, 'Location'),
            if (_names.isNotEmpty) ...[
              _gap(),
              _employeeDropdown(
                'Reports to',
                _reportingTo,
                (v) => setState(() => _reportingTo = v),
              ),
            ],
            _gap(),
            DropdownButtonFormField<String?>(
              initialValue: _employmentType,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Employment type',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Not specified'),
                ),
                for (final e in _employmentTypes.entries)
                  DropdownMenuItem<String?>(value: e.key, child: Text(e.value)),
              ],
              onChanged: (v) => setState(() => _employmentType = v),
            ),
            _gap(),
            _number(
              _positions,
              'Number of positions *',
              RequisitionRules.positions,
              key: const Key('f_positions'),
              decimal: false,
            ),
            _gap(),
            DropdownButtonFormField<String>(
              initialValue: _priority,
              decoration: const InputDecoration(
                labelText: 'Priority',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final p in _priorities)
                  DropdownMenuItem(
                    value: p,
                    child: Text(requisitionPriorityLabel(p)),
                  ),
              ],
              onChanged: (v) => setState(() => _priority = v ?? 'medium'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Replacement hire'),
              value: _isReplacement,
              onChanged: (v) => setState(() => _isReplacement = v),
            ),
            if (_isReplacement && _names.isNotEmpty) ...[
              _employeeDropdown(
                'Replacing',
                _replacing,
                (v) => setState(() => _replacing = v),
              ),
              _gap(),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _number(
                    _expMin,
                    'Experience min (yrs)',
                    RequisitionRules.experience,
                    key: const Key('f_exp_min'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _number(
                    _expMax,
                    'Experience max (yrs)',
                    (v) =>
                        RequisitionRules.experience(v) ??
                        RequisitionRules.range(
                          _expMin.text,
                          v,
                          'Max must be at least min',
                        ),
                    key: const Key('f_exp_max'),
                  ),
                ),
              ],
            ),
            _gap(),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _number(
                    _salMin,
                    'Salary min',
                    RequisitionRules.salary,
                    key: const Key('f_sal_min'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _number(
                    _salMax,
                    'Salary max',
                    (v) =>
                        RequisitionRules.salary(v) ??
                        RequisitionRules.range(
                          _salMin.text,
                          v,
                          'Max must be at least min',
                        ),
                    key: const Key('f_sal_max'),
                  ),
                ),
              ],
            ),
            _gap(),
            _text(
              _currency,
              'Currency (3 letters)',
              key: const Key('f_currency'),
              validator: RequisitionRules.currency,
            ),
            _gap(),
            _text(_skills, 'Key skills (comma separated)'),
            _gap(),
            _text(_quals, 'Qualifications (comma separated)'),
            _gap(),
            _text(_jd, 'Job description', lines: 3),
            _gap(),
            _text(_justification, 'Business justification', lines: 3),
            _gap(),
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.event_outlined),
              label: Text(
                _joining == null
                    ? 'Expected joining date'
                    : 'Expected joining: ${DateFormat('d MMM yyyy').format(_joining!)}',
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _error!,
                  style: GoogleFonts.montserrat(
                    fontSize: 12,
                    color: Colors.red[700],
                  ),
                ),
              ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving ? null : () => _save(submit: false),
                    child: Text(_rejected ? 'Save changes' : 'Save draft'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: _saving ? null : () => _save(submit: true),
                    child: const Text('Submit for approval'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
