import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../brew_admin.dart';
import '../../brew_counter.dart';
import '../../theme/brew_type.dart';
import '../../theme/tokens.dart';
import '../../widgets/brew_background.dart';
import '../../widgets/brew_field.dart';
import '../../widgets/brew_sheet.dart';
import '../whole_menu_screen.dart';
import 'admin_transitions.dart';

/// Screen where admins and super admins configure the full photographic
/// menu posters/boards for a shop.
///
/// Backed by the separate Firestore collection `shops/{partner.id}/whole_menu`.
class AdminWholeMenuScreen extends StatefulWidget {
  const AdminWholeMenuScreen({
    super.key,
    required this.partner,
    this.admin,
    this.counter,
  });

  final BrewPartner partner;
  final BrewAdmin? admin;
  final BrewCounter? counter;

  static Route<void> route({
    bool reduced = false,
    required BrewPartner partner,
    BrewAdmin? admin,
    BrewCounter? counter,
  }) {
    return adminPageRoute<void>(
      reduced: reduced,
      builder: (context) => AdminWholeMenuScreen(
        partner: partner,
        admin: admin,
        counter: counter,
      ),
    );
  }

  @override
  State<AdminWholeMenuScreen> createState() => _AdminWholeMenuScreenState();
}

class _AdminWholeMenuScreenState extends State<AdminWholeMenuScreen> {
  final _picker = ImagePicker();
  bool _busy = false;

  Future<void> _openAddBoardDialog({BrewWholeMenuBoard? existing}) async {
    final titleController = TextEditingController(text: existing?.title ?? '');
    final descController = TextEditingController(
      text: existing?.description ?? '',
    );
    final sortController = TextEditingController(
      text: existing != null ? existing.sort.toStringAsFixed(0) : '1',
    );
    Uint8List? selectedImage = existing?.imageBytes;
    bool isSaving = false;
    String? dialogError;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF0F2317),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: BrewColor.cream.withValues(alpha: 0.15)),
            ),
            title: Text(
              existing == null ? 'Add Menu Board' : 'Edit Menu Board',
              style: BrewType.displayAt(19).copyWith(color: BrewColor.cream),
            ),
            content: SingleChildScrollView(
              child: SizedBox(
                width: 360,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (dialogError != null) ...[
                      Text(
                        dialogError!,
                        style: BrewType.mono.copyWith(
                          color: const Color(0xFFE56B6F),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    // Image picker preview
                    GestureDetector(
                      onTap: isSaving
                          ? null
                          : () async {
                              try {
                                final file = await _picker.pickImage(
                                  source: ImageSource.gallery,
                                  maxWidth: 1600,
                                  maxHeight: 1600,
                                  imageQuality: 80,
                                );
                                if (file != null) {
                                  final bytes = await file.readAsBytes();
                                  setDialogState(() {
                                    selectedImage = bytes;
                                    dialogError = null;
                                  });
                                }
                              } catch (e) {
                                setDialogState(
                                  () =>
                                      dialogError = 'Could not pick image: $e',
                                );
                              }
                            },
                      child: Container(
                        height: 140,
                        decoration: BoxDecoration(
                          color: const Color(0x33000000),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(
                              0xFFD4A373,
                            ).withValues(alpha: 0.4),
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: selectedImage != null
                            ? Image.memory(
                                selectedImage!,
                                fit: BoxFit.cover,
                                width: double.infinity,
                                height: double.infinity,
                              )
                            : (existing?.assetPath != null
                                  ? Image.asset(
                                      existing!.assetPath!,
                                      fit: BoxFit.cover,
                                      width: double.infinity,
                                      height: double.infinity,
                                    )
                                  : Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            Icons.add_photo_alternate_rounded,
                                            size: 36,
                                            color: Color(0xFFD4A373),
                                          ),
                                          const SizedBox(height: 6),
                                          Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 16,
                                            ),
                                            child: Text(
                                              'Tap to choose board photo',
                                              textAlign: TextAlign.center,
                                              style: BrewType.mono.copyWith(
                                                fontSize: 11,
                                                color: BrewColor.cream
                                                    .withValues(alpha: 0.7),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    )),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Title
                    BrewField(
                      controller: titleController,
                      label: 'Board Title',
                      hint: 'e.g. Board 1 — Iced & Hot Beverages',
                    ),
                    const SizedBox(height: 12),

                    // Description
                    BrewField(
                      controller: descController,
                      label: 'Subtitle / Description (optional)',
                      hint: 'e.g. Classic Coffees & Frappe Series',
                    ),
                    const SizedBox(height: 12),

                    // Sort order
                    BrewField(
                      controller: sortController,
                      label: 'Sort Position (1, 2, 3...)',
                      hint: '1',
                      keyboardType: TextInputType.number,
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSaving ? null : () => Navigator.of(ctx).pop(),
                child: Text(
                  'Cancel',
                  style: BrewType.mono.copyWith(color: BrewColor.cream),
                ),
              ),
              ElevatedButton(
                onPressed: isSaving
                    ? null
                    : () async {
                        final title = titleController.text.trim();
                        if (title.isEmpty) {
                          setDialogState(
                            () => dialogError = 'Please provide a title.',
                          );
                          return;
                        }

                        if (selectedImage == null &&
                            existing?.assetPath == null) {
                          setDialogState(
                            () => dialogError =
                                'Please pick a board photo to upload.',
                          );
                          return;
                        }

                        setDialogState(() {
                          isSaving = true;
                          dialogError = null;
                        });

                        final admin = widget.admin;
                        if (admin == null) {
                          setDialogState(
                            () => dialogError =
                                'Admin service unavailable (offline).',
                          );
                          return;
                        }

                        final boardId =
                            existing?.id ??
                            'board_${DateTime.now().millisecondsSinceEpoch}';
                        final sort =
                            double.tryParse(sortController.text) ?? 1.0;

                        final err = await admin.saveWholeMenuBoard(
                          partner: widget.partner,
                          boardId: boardId,
                          title: title,
                          description: descController.text.trim(),
                          imageBytes: selectedImage,
                          sort: sort,
                        );

                        if (err != null) {
                          setDialogState(() {
                            isSaving = false;
                            dialogError = err;
                          });
                        } else {
                          if (ctx.mounted) Navigator.of(ctx).pop();
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF487A5E),
                  foregroundColor: BrewColor.cream,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                child: Text(isSaving ? 'Saving…' : 'Save Board'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _deleteBoard(BrewWholeMenuBoard board) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F2317),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: BrewColor.cream.withValues(alpha: 0.15)),
        ),
        title: Text(
          'Delete Menu Board?',
          style: BrewType.displayAt(18).copyWith(color: BrewColor.cream),
        ),
        content: Text(
          'Are you sure you want to remove "${board.title}" from this shop\'s whole menu collection?',
          style: BrewType.rowBody.copyWith(color: BrewColor.cream),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancel',
              style: BrewType.mono.copyWith(color: BrewColor.cream),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF8B263E),
              foregroundColor: BrewColor.cream,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _busy = true);
    final admin = widget.admin;
    if (admin != null) {
      final err = await admin.deleteWholeMenuBoard(
        partner: widget.partner,
        boardId: board.id,
      );
      if (mounted && err != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(err), backgroundColor: BrewColor.alert),
        );
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  void _previewWholeMenu() {
    Navigator.of(context).push(
      WholeMenuViewerScreen.route(
        shop: BrewShop(partner: widget.partner, status: BrewShopStatus.open),
        counter: widget.counter,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BrewColor.field,
      body: BrewBackground(
        child: BrewSheet(
          staggerCount: 6,
          children: [
            // Top navigation & title
            Row(
              children: [
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => Navigator.of(context).pop(),
                    borderRadius: BorderRadius.circular(999),
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0x33132B1E),
                        border: Border.all(
                          color: BrewColor.cream.withValues(alpha: 0.15),
                        ),
                      ),
                      child: const Icon(
                        Icons.arrow_back_rounded,
                        size: 20,
                        color: BrewColor.cream,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Whole Menu Posters',
                        style: BrewType.displayAt(
                          22,
                        ).copyWith(color: BrewColor.cream),
                      ),
                      Text(
                        '${widget.partner.name} — Configurable collection',
                        style: BrewType.mono.copyWith(
                          fontSize: 11,
                          color: const Color(0xFFD4A373),
                        ),
                      ),
                    ],
                  ),
                ),
                // Preview full viewer button
                IconButton(
                  tooltip: 'Preview Customer Viewer',
                  onPressed: _previewWholeMenu,
                  icon: const Icon(
                    Icons.visibility_rounded,
                    color: Color(0xFFD4A373),
                  ),
                ),
              ],
            ),
            const SizedBox(height: BrewSpace.grid * 2),

            // Description info card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xEB132218),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: BrewColor.cream.withValues(alpha: 0.12),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.collections_bookmark_rounded,
                        size: 20,
                        color: Color(0xFF5BA37E),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Firestore Collection: whole_menu',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: BrewType.mono.copyWith(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: BrewColor.cream,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Upload high-resolution photographic boards shown when customers tap "View whole menu". Changes sync in real time.',
                    style: BrewType.rowBody.copyWith(
                      fontSize: 12,
                      color: BrewColor.cream.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: BrewSpace.grid * 2),

            // Live boards list
            StreamBuilder<List<BrewWholeMenuBoard>>(
              stream:
                  widget.admin?.wholeMenuFor(widget.partner) ??
                  widget.counter?.wholeMenu(widget.partner),
              initialData: BrewWholeMenuBoard.defaultsFor(widget.partner),
              builder: (context, snapshot) {
                // A failed read leaves the snapshot with no data at all, which
                // used to draw as "(0)" and "No menu boards configured" — a
                // claim about the shop that nobody had checked. The customer
                // viewer shows the bundled posters in that state, so this list
                // does too, and says why.
                final unreachable = snapshot.hasError;
                final boards =
                    snapshot.data ??
                    (unreachable
                        ? BrewWholeMenuBoard.defaultsFor(widget.partner)
                        : const <BrewWholeMenuBoard>[]);

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (unreachable) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: BrewColor.alert.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: BrewColor.alert.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Text(
                          'Could not load the saved boards, so the built-in '
                          'posters are shown. Uploads and edits will not save '
                          'until this is fixed.',
                          style: BrewType.rowBody.copyWith(
                            fontSize: 12,
                            color: BrewColor.alert,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'CONFIGURED BOARDS (${boards.length})',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: BrewType.mono.copyWith(
                              fontSize: 11,
                              letterSpacing: 1.2,
                              fontWeight: FontWeight.w700,
                              color: BrewColor.cream.withValues(alpha: 0.6),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: _busy ? null : () => _openAddBoardDialog(),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0x33487A5E),
                            foregroundColor: BrewColor.cream,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(999),
                              side: const BorderSide(color: Color(0x66487A5E)),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                          ),
                          icon: const Icon(Icons.add_rounded, size: 16),
                          label: const Text('Add Board'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    if (boards.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: const Color(0x33000000),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: BrewColor.hairline),
                        ),
                        child: Center(
                          child: Text(
                            'No menu boards configured yet. Tap "Add Board" to upload one.',
                            textAlign: TextAlign.center,
                            style: BrewType.rowBody.copyWith(
                              color: BrewColor.cream.withValues(alpha: 0.6),
                            ),
                          ),
                        ),
                      ),

                    for (final board in boards) ...[
                      _AdminBoardCard(
                        board: board,
                        onEdit: () => _openAddBoardDialog(existing: board),
                        onDelete: () => _deleteBoard(board),
                        onPreview: _previewWholeMenu,
                      ),
                      const SizedBox(height: 12),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminBoardCard extends StatelessWidget {
  const _AdminBoardCard({
    required this.board,
    required this.onEdit,
    required this.onDelete,
    required this.onPreview,
  });

  final BrewWholeMenuBoard board;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onPreview;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xEB132218),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: BrewColor.cream.withValues(alpha: 0.12)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Thumbnail
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: const Color(0x33000000),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: BrewColor.cream.withValues(alpha: 0.15),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: board.imageBytes != null
                ? Image.memory(board.imageBytes!, fit: BoxFit.cover)
                : (board.assetPath != null
                      ? Image.asset(board.assetPath!, fit: BoxFit.cover)
                      : const Icon(
                          Icons.broken_image_rounded,
                          color: BrewColor.cream,
                        )),
          ),
          const SizedBox(width: 14),

          // Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0x33D4A373),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '#${board.sort.toStringAsFixed(0)}',
                        style: BrewType.mono.copyWith(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFFD4A373),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        board.title,
                        style: BrewType.title.copyWith(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: BrewColor.cream,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  board.description ?? 'Full menu poster board',
                  style: BrewType.rowBody.copyWith(
                    fontSize: 12,
                    color: BrewColor.cream.withValues(alpha: 0.65),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Actions
          IconButton(
            tooltip: 'Preview',
            icon: const Icon(Icons.visibility_rounded, size: 18),
            color: BrewColor.cream.withValues(alpha: 0.8),
            onPressed: onPreview,
          ),
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_rounded, size: 18),
            color: const Color(0xFF5BA37E),
            onPressed: onEdit,
          ),
          IconButton(
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            color: const Color(0xFFE56B6F),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}
