import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../widgets/employee_ui.dart';

class SurveyResponseScreen extends StatefulWidget {
  final Map<String, dynamic> survey;
  final String employeeId;
  final String organizationId;
  final String userEmail;

  const SurveyResponseScreen({
    Key? key,
    required this.survey,
    required this.employeeId,
    required this.organizationId,
    required this.userEmail,
  }) : super(key: key);

  @override
  State<SurveyResponseScreen> createState() =>
      _SurveyResponseScreenState();
}

class _SurveyResponseScreenState
    extends State<SurveyResponseScreen> {
final supabase = Supabase.instance.client;

bool loading = false;

/// Stores answers
final Map<String, dynamic> responses = {};

List<Map<String, dynamic>> get questions {
final q = widget.survey['questions'];

if (q is List) {
return q.map((e) => Map<String, dynamic>.from(e)).toList();
}

return [];
}

Future<void> submitSurvey() async {
final requiredQuestions = questions.where(
(q) => q['required'] == true,
);

for (final q in requiredQuestions) {
final ans = responses[q['id']];

if (ans == null ||
(ans is String && ans.trim().isEmpty)) {
ScaffoldMessenger.of(context).showSnackBar(
const SnackBar(
content:
Text("Please answer all required questions"),
),
);
return;
}
}

try {
setState(() {
loading = true;
});

final payload = questions
.map(
(q) => {
"question_id": q["id"],
"question_text": q["text"],
"answer": responses[q["id"]],
},
)
.toList();

await supabase.from("survey_responses").insert({
"survey_id": widget.survey["id"],
"employee_id": widget.employeeId,
"responses": payload,
});

if (!mounted) return;

Navigator.pop(context, true);
} on PostgrestException catch (e) {
if (!mounted) return;

if (e.code == "23505") {
ScaffoldMessenger.of(context).showSnackBar(
const SnackBar(
content:
Text("You have already submitted this survey."),
),
);
} else {
ScaffoldMessenger.of(context).showSnackBar(
SnackBar(content: Text(e.message)),
);
}
} finally {
if (mounted) {
setState(() {
loading = false;
});
}
}
}

Widget buildQuestion(Map<String, dynamic> q) {
final type = q["type"] ?? "text";

switch (type) {
case "multiple-choice":
return buildMultipleChoice(q);

case "yes-no":
return buildYesNo(q);

case "rating":
return buildRating(q);

default:
return buildText(q);
}
}

Widget buildText(Map<String, dynamic> q) {
return TextField(
maxLines: 3,
decoration: InputDecoration(
border: OutlineInputBorder(
borderRadius: BorderRadius.circular(12),
),
),
onChanged: (v) {
responses[q["id"]] = v;
},
);
}

Widget buildYesNo(Map<String, dynamic> q) {
return Column(
children: [
RadioListTile<String>(
value: "yes",
groupValue: responses[q["id"]],
title: const Text("Yes"),
onChanged: (v) {
setState(() {
responses[q["id"]] = v;
});
},
),
RadioListTile<String>(
value: "no",
groupValue: responses[q["id"]],
title: const Text("No"),
onChanged: (v) {
setState(() {
responses[q["id"]] = v;
});
},
),
],
);
}
Widget buildRating(Map<String, dynamic> q) {
  final value = responses[q["id"]] as int?;

  return Row(
    children: List.generate(5, (index) {
      final rating = index + 1;

      return IconButton(
        onPressed: () {
          setState(() {
            responses[q["id"]] = rating;
          });
        },
        icon: Icon(
          value != null && value >= rating
              ? Icons.star
              : Icons.star_border,
          color: Colors.amber,
          size: 32,
        ),
      );
    }),
  );
}

Widget buildMultipleChoice(Map<String, dynamic> q) {
  final options = List<String>.from(q["options"] ?? []);

  return Column(
    children: options.map((option) {
      return RadioListTile<String>(
        value: option,
        groupValue: responses[q["id"]],
        title: Text(option),
        onChanged: (v) {
          setState(() {
            responses[q["id"]] = v;
          });
        },
      );
    }).toList(),
  );
}

@override
Widget build(BuildContext context) {
  return Scaffold(
    backgroundColor: EmployeeUi.pageBg,
    appBar: AppBar(
      elevation: 0,
      backgroundColor: Colors.white,
      foregroundColor: Colors.black,
      title: Text(
        widget.survey["title"] ?? "Survey",
        style: EmployeeUi.header(20),
      ),
    ),
    body: Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [

              if ((widget.survey["description"] ?? "")
                  .toString()
                  .isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: EmployeeUi.cardDecoration(),
                  child: Text(
                    widget.survey["description"],
                    style: GoogleFonts.montserrat(
                      fontSize: 14,
                    ),
                  ),
                ),

              ...questions.map((q) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 18),
                  padding: const EdgeInsets.all(18),
                  decoration: EmployeeUi.cardDecoration(),
                  child: Column(
                    crossAxisAlignment:
                    CrossAxisAlignment.start,
                    children: [

                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              q["text"] ?? "",
                              style: EmployeeUi.title(15),
                            ),
                          ),

                          if (q["required"] == true)
                            const Text(
                              "*",
                              style: TextStyle(
                                color: Colors.red,
                                fontSize: 18,
                              ),
                            ),
                        ],
                      ),

                      const SizedBox(height: 14),

                      buildQuestion(q),
                    ],
                  ),
                );
              }).toList(),
            ],
          ),
        ),

        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed:
                loading ? null : submitSurvey,
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                  EmployeeUi.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius:
                    BorderRadius.circular(14),
                  ),
                ),
                child: loading
                    ? const SizedBox(
                  width: 22,
                  height: 22,
                  child:
                  CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
                    : const Text(
                  "Submit Survey",
                  style: TextStyle(
                    fontWeight:
                    FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
}