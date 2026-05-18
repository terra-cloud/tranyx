import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:tranyx_web/services/web_interop.dart';
import '../components/job_category_selector.dart';
import 'package:shared/shared.dart';
import '../services/firebase_service.dart';

@client
class PostJobPage extends StatefulComponent {
  const PostJobPage({super.key});

  @override
  State<PostJobPage> createState() => PostJobPageState();
}

class PostJobPageState extends State<PostJobPage> {
  CategoryItem? _selectedCategory;
  int _step = 1;

  String _title = '';
  String _rate = '';
  String _description = '';
  bool _isGenerating = false;
  final _gemini = GeminiService(currentFirebaseConfig, idToken: SessionStorage.idToken);

  void _onCategorySelected(CategoryItem category) {
    setState(() {
      _selectedCategory = category;
      _step = 2;
    });
  }

  Future<void> _generateDescription() async {
    if (_title.isEmpty || _selectedCategory == null) return;

    setState(() => _isGenerating = true);
    try {
      final prompt =
          'Write a concise, professional job description for a gig titled "$_title" in the category "${_selectedCategory!.label}". Rate is $_rate. Explain what the gig entails and what expectations the worker should meet.';
      final result = await _gemini.generateJobDescription(prompt);
      setState(() {
        _description = result;
        _isGenerating = false;
      });
    } catch (e) {
      setState(() => _isGenerating = false);
    }
  }

  @override
  Component build(BuildContext context) {
    return section(classes: 'min-h-screen py-12 px-4 max-w-6xl mx-auto', [
      // Header Section
      div(classes: 'mb-12 text-center animate-fade-up', [
        h1(classes: 'text-4xl md:text-5xl font-extrabold text-zinc-100 mb-4 tracking-tight', [
          Component.text('Post a new '),
          span(classes: 'text-indigo-500', [Component.text('Gig')]),
        ]),
        p(classes: 'text-zinc-400 text-lg max-w-2xl mx-auto', [
          Component.text('Tell us what you need help with and we\'ll connect you with the best Nyxians in your area.'),
        ]),
      ]),

      // Step Progress
      div(classes: 'flex justify-center mb-16', [
        div(classes: 'flex items-center gap-4', [
          _buildStepIndicator(1, 'Category', _step >= 1),
          div(classes: 'w-12 h-0.5 bg-zinc-800', []),
          _buildStepIndicator(2, 'Details', _step >= 2),
          div(classes: 'w-12 h-0.5 bg-zinc-800', []),
          _buildStepIndicator(3, 'Review', _step >= 3),
        ]),
      ]),

      if (_step == 1) ...[
        JobCategorySelector(
          onCategorySelected: _onCategorySelected,
          selectedCategory: _selectedCategory,
        ),
      ] else if (_step == 2) ...[
        _buildJobDetailsForm(),
      ],
    ]);
  }

  Component _buildStepIndicator(int num, String label, bool active) {
    return div(classes: 'flex flex-col items-center gap-2', [
      div(
        classes:
            'w-10 h-10 rounded-full flex items-center justify-center font-bold transition-all duration-500 '
            '${active ? 'bg-indigo-600 text-white shadow-[0_0_15px_rgba(79,70,229,0.4)]' : 'bg-zinc-900 text-zinc-500 border border-zinc-800'}',
        [Component.text(num.toString())],
      ),
      span(classes: 'text-xs font-medium ${active ? 'text-indigo-400' : 'text-zinc-500'}', [Component.text(label)]),
    ]);
  }

  Component _buildJobDetailsForm() {
    return div(classes: 'max-w-2xl mx-auto bg-zinc-900/50 border border-zinc-800 p-8 rounded-3xl animate-fade-up', [
      div(classes: 'flex items-center gap-4 mb-8', [
        button(
          classes: 'p-2 rounded-xl bg-zinc-800 text-zinc-400 hover:text-white transition-colors',
          onClick: () => setState(() => _step = 1),
          [
            i([], classes: 'w-5 h-5', attributes: {'data-lucide': 'arrow-left'}),
          ],
        ),
        div([
          h2(classes: 'text-xl font-bold text-zinc-100', [Component.text(_selectedCategory?.label ?? 'Job Details')]),
          p(classes: 'text-sm text-zinc-500', [Component.text('Provide more information about your request')]),
        ]),
      ]),

      div(classes: 'space-y-6', [
        _buildInputField(
          'Title',
          'e.g. Need a plumber for leaky faucet',
          InputType.text,
          _title,
          (v) => setState(() => _title = v),
        ),
        _buildInputField('Rate', 'e.g. 500', InputType.number, _rate, (v) => setState(() => _rate = v)),
        div(classes: 'space-y-2 relative', [
          label(classes: 'block text-sm font-medium text-zinc-400', [Component.text('Description')]),
          textarea(
            classes:
                'w-full bg-zinc-950 border border-zinc-800 rounded-xl p-4 text-zinc-100 focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500 transition-all outline-none min-h-[160px] pb-12',
            attributes: {
              'placeholder': 'Describe the work in detail...',
            },
            events: {
              'input': (e) {
                // ignore: avoid_dynamic_calls
                setState(() => _description = (e as dynamic).target.value as String);
              },
            },
            [Component.text(_description)],
          ),
          button(
            classes:
                'absolute bottom-4 right-4 flex items-center gap-2 px-3 py-1.5 rounded-lg text-xs font-bold transition-all ${_isGenerating ? 'bg-zinc-800 text-zinc-500 cursor-not-allowed' : 'bg-indigo-500/10 text-indigo-400 hover:bg-indigo-500/20 active:scale-95'}',
            events: {
              'click': (e) {
                e.preventDefault();
                if (!_isGenerating) _generateDescription();
              },
            },
            [
              if (_isGenerating) ...[
                i([], classes: 'w-3 h-3 animate-spin', attributes: {'data-lucide': 'loader-2'}),
                Component.text('Generating...'),
              ] else ...[
                i([], classes: 'w-3 h-3', attributes: {'data-lucide': 'sparkles'}),
                Component.text('Auto-write'),
              ],
            ],
          ),
        ]),
        button(
          classes:
              'w-full bg-indigo-600 hover:bg-indigo-500 text-white font-bold py-4 rounded-xl transition-all shadow-lg shadow-indigo-500/20 active:scale-[0.98]',
          [Component.text('Continue to Review')],
        ),
      ]),
    ]);
  }

  Component _buildInputField(
    String labelText,
    String placeholder,
    InputType type,
    String value,
    void Function(String) onChange,
  ) {
    return div(classes: 'space-y-2', [
      label(classes: 'block text-sm font-medium text-zinc-400', [Component.text(labelText)]),
      input(
        classes:
            'w-full bg-zinc-950 border border-zinc-800 rounded-xl p-4 text-zinc-100 focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500 transition-all outline-none',
        type: type,
        attributes: {'placeholder': placeholder, 'value': value},
        events: {
          'input': (e) {
            // ignore: avoid_dynamic_calls
            onChange((e as dynamic).target.value as String);
          },
        },
      ),
    ]);
  }
}
