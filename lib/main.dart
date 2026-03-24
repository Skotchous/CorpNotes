import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';

// РЕШЕНИЕ ОШИБКИ С CONTEXT: импортируем библиотеку с алиасом "p"
import 'package:path/path.dart' as p; 
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

// РЕШЕНИЕ ОШИБКИ С MyApp: Запускаем класс MyApp
void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CorpNotes',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blueGrey,
        scaffoldBackgroundColor: Colors.grey[100],
      ),
      home: const NotesScreen(),
    );
  }
}

// ================= MODEL =================
class Note {
  int? id;
  String title;
  String content;
  String dateTime;

  Note({this.id, required this.title, required this.content, required this.dateTime});

  Map<String, dynamic> toMap() {
    return {'id': id, 'title': title, 'content': content, 'dateTime': dateTime};
  }

  factory Note.fromMap(Map<String, dynamic> map) {
    return Note(
      id: map['id'],
      title: map['title'],
      content: map['content'],
      dateTime: map['dateTime'],
    );
  }
}

// ================= STORAGE LOGIC =================
class StorageService {
  bool useSQLite = true;
  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }

  Future<Database> _initDB() async {
    // Используем p.join для пути (ошибки Context больше не будет)
    String path = p.join(await getDatabasesPath(), 'corp_notes.db');
    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute(
            'CREATE TABLE notes(id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT, content TEXT, dateTime TEXT)');
      },
    );
  }

  Future<File> get _file async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/notes_data.json');
  }

  Future<List<Note>> getNotes() async {
    if (useSQLite) {
      final db = await database;
      final List<Map<String, dynamic>> maps = await db.query('notes', orderBy: 'id DESC');
      return List.generate(maps.length, (i) => Note.fromMap(maps[i]));
    } else {
      try {
        final file = await _file;
        if (!await file.exists()) return [];
        String contents = await file.readAsString();
        List<dynamic> jsonList = jsonDecode(contents);
        return jsonList.map((json) => Note.fromMap(json)).toList().reversed.toList();
      } catch (e) {
        return [];
      }
    }
  }

  Future<void> saveNote(Note note) async {
    if (useSQLite) {
      final db = await database;
      if (note.id == null) {
        await db.insert('notes', note.toMap());
      } else {
        await db.update('notes', note.toMap(), where: 'id = ?', whereArgs: [note.id]);
      }
    } else {
      List<Note> notes = await getNotes();
      notes = notes.reversed.toList(); 
      if (note.id == null) {
        note.id = DateTime.now().millisecondsSinceEpoch;
        notes.add(note);
      } else {
        int index = notes.indexWhere((n) => n.id == note.id);
        if (index != -1) notes[index] = note;
      }
      final file = await _file;
      await file.writeAsString(jsonEncode(notes.map((n) => n.toMap()).toList()));
    }
  }

  Future<void> deleteNote(int id) async {
    if (useSQLite) {
      final db = await database;
      await db.delete('notes', where: 'id = ?', whereArgs: [id]);
    } else {
      List<Note> notes = await getNotes();
      notes.removeWhere((n) => n.id == id);
      final file = await _file;
      await file.writeAsString(jsonEncode(notes.map((n) => n.toMap()).toList()));
    }
  }
}

// ================= UI MAIN SCREEN =================
class NotesScreen extends StatefulWidget {
  const NotesScreen({Key? key}) : super(key: key);

  @override
  _NotesScreenState createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  final StorageService _storage = StorageService();
  List<Note> _notes = [];
  List<Note> _filteredNotes = [];
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadNotes();
  }

  void _loadNotes() async {
    final notes = await _storage.getNotes();
    setState(() {
      _notes = notes;
      _filterNotes(_searchQuery);
    });
  }

  void _filterNotes(String query) {
    setState(() {
      _searchQuery = query;
      _filteredNotes = _notes
          .where((note) =>
              note.title.toLowerCase().contains(query.toLowerCase()) ||
              note.content.toLowerCase().contains(query.toLowerCase()) ||
              note.dateTime.contains(query))
          .toList();
    });
  }

  void _toggleStorage() {
    setState(() {
      _storage.useSQLite = !_storage.useSQLite;
      _loadNotes(); 
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Хранилище: ${_storage.useSQLite ? "База данных SQLite" : "Файлы JSON"}'),
      duration: const Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('CorpNotes'),
        actions: [
          IconButton(
            icon: Icon(_storage.useSQLite ? Icons.storage : Icons.folder),
            tooltip: 'Сменить хранилище',
            onPressed: _toggleStorage,
          )
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              decoration: InputDecoration(
                labelText: 'Поиск заметок...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                fillColor: Colors.white,
                filled: true,
              ),
              onChanged: _filterNotes,
            ),
          ),
          Expanded(
            child: _filteredNotes.isEmpty
                ? const Center(child: Text('Нет заметок. Нажмите "+" для создания.'))
                : ListView.builder(
                    itemCount: _filteredNotes.length,
                    itemBuilder: (context, index) {
                      final note = _filteredNotes[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        elevation: 2,
                        child: ListTile(
                          title: Text(note.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text('${note.dateTime}\n${note.content}',
                              maxLines: 2, overflow: TextOverflow.ellipsis),
                          isThreeLine: true,
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.redAccent),
                            onPressed: () async {
                              await _storage.deleteNote(note.id!);
                              _loadNotes();
                            },
                          ),
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => NoteEditorScreen(note: note, storage: _storage)),
                            );
                            _loadNotes();
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add),
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => NoteEditorScreen(storage: _storage)),
          );
          _loadNotes();
        },
      ),
    );
  }
}

// ================= UI EDITOR SCREEN =================
class NoteEditorScreen extends StatefulWidget {
  final Note? note;
  final StorageService storage;

  const NoteEditorScreen({Key? key, this.note, required this.storage}) : super(key: key);

  @override
  _NoteEditorScreenState createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen> {
  late TextEditingController _titleController;
  late TextEditingController _contentController;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.note?.title ?? '');
    _contentController = TextEditingController(text: widget.note?.content ?? '');
  }

  void _saveNote() async {
    if (_titleController.text.trim().isEmpty) return;

    String now = DateTime.now().toString().substring(0, 16);

    final note = Note(
      id: widget.note?.id,
      title: _titleController.text,
      content: _contentController.text,
      dateTime: now,
    );

    await widget.storage.saveNote(note);
    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.note == null ? 'Новая заметка' : 'Редактирование'),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: _saveNote,
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Заголовок (например, Совещание)',
                border: InputBorder.none,
              ),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const Divider(),
            Expanded(
              child: TextField(
                controller: _contentController,
                decoration: const InputDecoration(
                  labelText: 'Содержание заметки...',
                  border: InputBorder.none,
                ),
                maxLines: null,
                keyboardType: TextInputType.multiline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}