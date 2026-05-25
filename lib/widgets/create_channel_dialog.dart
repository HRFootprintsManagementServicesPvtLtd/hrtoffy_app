import 'package:flutter/material.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

class CreateChannelDialog
    extends StatefulWidget {

  final Function() onCreated;

  const CreateChannelDialog({

    super.key,

    required this.onCreated,
  });

  @override
  State<CreateChannelDialog>
  createState() =>
      _CreateChannelDialogState();
}

class _CreateChannelDialogState
    extends State<CreateChannelDialog> {

  final supabase =
      Supabase.instance.client;

  final TextEditingController
  nameController =
  TextEditingController();

  final TextEditingController
  descriptionController =
  TextEditingController();

  List employees = [];

  List selected = [];

  bool loading = true;

  @override
  void initState() {

    super.initState();

    loadEmployees();
  }

  Future<void> loadEmployees() async {

    final currentUser =
        supabase.auth.currentUser;

    final result = await supabase
        .from('employee_records')
        .select();

    employees = result.where((e) {

      return e['user_id'] !=
          currentUser?.id;

    }).toList();

    setState(() {
      loading = false;
    });
  }

  Future<void> createChannel()
  async {

    try {

      final currentUser =
      supabase.auth.currentUser!;

      final currentEmployee = await supabase
          .from('employee_records')
          .select('organization_id')
          .eq(
        'user_id',
        currentUser.id,
      )
          .single();

      final channel =
      await supabase
          .from('chat_channels')
          .insert({

        'organization_id':
        currentEmployee['organization_id'],

        'name': nameController.text,

        'title': nameController.text,

        'description':
        descriptionController.text,

        'channel_type': 'group',

      }).select().single();

      await supabase
          .from('chat_channel_members')
          .insert({

        'channel_id': channel['id'],

        'user_id': currentUser.id,
      });

      for (final employee
      in selected) {

        await supabase
            .from(
          'chat_channel_members',
        )
            .insert({

          'channel_id': channel['id'],

          'user_id':
          employee['user_id'],
        });
      }

      Navigator.pop(context);

      widget.onCreated();

    } catch (e) {

      debugPrint(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {

    return Dialog(

      backgroundColor: Colors.white,

      shape: RoundedRectangleBorder(
        borderRadius:
        BorderRadius.circular(24),
      ),

      child: Container(

        padding: const EdgeInsets.all(20),

        height: 600,

        child: loading

            ? const Center(
          child:
          CircularProgressIndicator(),
        )

            : Column(

          crossAxisAlignment:
          CrossAxisAlignment.start,

          children: [

            const Text(

              "Create Group Channel",

              style: TextStyle(

                fontSize: 22,

                fontWeight:
                FontWeight.w700,
              ),
            ),

            const SizedBox(height: 20),

            TextField(

              controller:
              nameController,

              decoration:
              const InputDecoration(

                labelText:
                "Channel name",
              ),
            ),

            const SizedBox(height: 14),

            TextField(

              controller:
              descriptionController,

              maxLines: 3,

              decoration:
              const InputDecoration(

                labelText:
                "Description",
              ),
            ),

            const SizedBox(height: 20),

            const Text(

              "Add Members",

              style: TextStyle(
                fontWeight:
                FontWeight.w700,
              ),
            ),

            const SizedBox(height: 12),

            Expanded(

              child: ListView.builder(

                itemCount:
                employees.length,

                itemBuilder:
                    (context, index) {

                  final employee =
                  employees[index];

                  final selectedUser =
                  selected.contains(
                    employee,
                  );

                  return CheckboxListTile(

                    value:
                    selectedUser,

                    title: Text(
                      employee[
                      'full_name'] ??
                          '',
                    ),

                    subtitle: Text(
                      employee[
                      'department'] ??
                          '',
                    ),

                    onChanged: (_) {

                      setState(() {

                        if (selectedUser) {

                          selected
                              .remove(
                            employee,
                          );

                        } else {

                          selected
                              .add(
                            employee,
                          );
                        }
                      });
                    },
                  );
                },
              ),
            ),

            const SizedBox(height: 20),

            SizedBox(

              width: double.infinity,

              child: ElevatedButton(

                onPressed:
                createChannel,

                child: const Text(
                  "Create Channel",
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
