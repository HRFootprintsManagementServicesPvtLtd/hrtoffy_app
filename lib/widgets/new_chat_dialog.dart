import 'package:flutter/material.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../screens/chat_thread_screen.dart';

class NewChatDialog extends StatefulWidget {

  final Function() onCreated;

  const NewChatDialog({

    super.key,

    required this.onCreated,
  });

  @override
  State<NewChatDialog> createState() =>
      _NewChatDialogState();
}

class _NewChatDialogState
    extends State<NewChatDialog> {

  final supabase =
      Supabase.instance.client;

  List employees = [];


  bool loading = true;

  @override
  void initState() {

    super.initState();

    loadEmployees();
  }

  Future<void> loadEmployees() async {

    try {

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

    } catch (e) {

      debugPrint(e.toString());

      setState(() {
        loading = false;
      });
    }
  }

  Future<void> createDM(
      Map employee,
      ) async {

    try {

      final currentUser =
      supabase.auth.currentUser!;

      final existing =
      await supabase
          .from('chat_channel_members')
          .select('channel_id')
          .eq(
        'user_id',
        currentUser.id,
      );

      for (final row in existing) {

        final channelId =
        row['channel_id'];

        final members =
        await supabase
            .from(
          'chat_channel_members',
        )
            .select()
            .eq(
          'channel_id',
          channelId,
        );

        final hasEmployee =
        members.any((m) {

          return m['user_id'] ==
              employee['user_id'];
        });

        if (members.length == 2 &&
            hasEmployee) {

          Navigator.pop(context);

          widget.onCreated();

          return;
        }
      }

      final channel =
      await supabase
          .from('chat_channels')
          .insert({

        'channel_type': 'dm',

      }).select().single();

      await supabase
          .from('chat_channel_members')
          .insert({

        'channel_id': channel['id'],

        'user_id': currentUser.id,
      });

      await supabase
          .from('chat_channel_members')
          .insert({

        'channel_id': channel['id'],

        'user_id': employee['user_id'],
      });

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

        height: 500,

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

              "New Direct Message",

              style: TextStyle(

                fontSize: 22,

                fontWeight:
                FontWeight.w700,
              ),
            ),

            const SizedBox(height: 20),

            TextField(

              decoration: InputDecoration(

                hintText:
                "Search employees...",

                prefixIcon:
                const Icon(Icons.search),

                border:
                OutlineInputBorder(

                  borderRadius:
                  BorderRadius.circular(
                    16,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),

            Expanded(

              child: ListView.builder(

                itemCount:
                employees.length,

                itemBuilder: (context, index) {

                  final employee = employees[index];

                  return ListTile(

                    onTap: () async {

                      final supabase =
                          Supabase.instance.client;

                      final currentUserId =
                          supabase.auth.currentUser!.id;

                      final selectedUserId =
                      employee['user_id'];

                      final existing = await supabase
                          .from('chat_channels')
                          .select()
                          .eq('channel_type', 'dm');

                      String? channelId;

                      for (final channel in existing) {



                        final members = await supabase
                            .from('chat_channel_members')
                            .select()
                            .eq('channel_id', channel['id']);

                        final ids = members
                            .map((e) => e['user_id'])
                            .toList();

                        if (ids.contains(currentUserId) &&
                            ids.contains(selectedUserId) &&
                            ids.length == 2) {

                          channelId = channel['id'];
                          break;
                        }
                      }

                      if (channelId == null) {

                        final currentEmployee = await supabase
                            .from('employee_records')
                            .select('organization_id')
                            .eq(
                          'user_id',
                          currentUserId,
                        )
                            .single();

                        final created = await supabase
                            .from('chat_channels')
                            .insert({

                          'organization_id':
                          currentEmployee['organization_id'],

                          'channel_type': 'dm',

                          'name': employee['full_name'],

                          'title': employee['full_name'],

                        })
                            .select()
                            .single();

                        channelId = created['id'];

                        await supabase
                            .from('chat_channel_members')
                            .insert({
                          'channel_id': channelId,
                          'user_id': currentUserId,
                        });

                        await supabase
                            .from('chat_channel_members')
                            .insert({
                          'channel_id': channelId,
                          'user_id': selectedUserId,
                        });
                      }

                      if (context.mounted) {

                        Navigator.pop(context);

                        Navigator.push(
                          context,

                          MaterialPageRoute(

                            builder: (_) => ChatThreadScreen(
                              channelId: channelId!,
                              title: employee['full_name'],
                            ),
                          ),
                        );
                      }
                    },

                    leading: CircleAvatar(
                      child: Text(
                        employee['full_name'][0],
                      ),
                    ),

                    title: Text(
                      employee['full_name'],
                    ),

                    subtitle: Text(
                      employee['department'] ?? '',
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
