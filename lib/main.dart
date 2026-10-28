import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'banco_sessoes.dart';
import 'sessao_estudo.dart';
import 'dart:io';

void main() {
  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  runApp(const SessaoApp());
}

class SessaoApp extends StatelessWidget {
  const SessaoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: TelaInicio(),
    );
  }
}

class TelaInicio extends StatefulWidget {
  const TelaInicio({super.key});

  @override
  State<TelaInicio> createState() => _TelaInicioState();
}

class _TelaInicioState extends State<TelaInicio> {
  final _banco = BancoSessoes();
  List<SessaoEstudo> _sessoes = [];
  bool _carregando = true;
  bool _ocupado = false;
  String? _erro;

  @override
  void initState() {
    super.initState();
    carregarSessoes();
  }

  Future<void> carregarSessoes() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final sessoes = await _banco.listar();
      if (!mounted) return;
      setState(() => _sessoes = sessoes);
    } catch (erro) {
      debugPrint('Falha ao consultar sessões: $erro');
      if (!mounted) return;
      setState(() => _erro = 'Não foi possível consultar. Tente novamente.');
    } finally {
      if (mounted) {
        setState(() => _carregando = false);
      }
    }
  }

  String resumoSessao() {
    if (_carregando) return 'Consultando sessões...';
    if (_erro != null) return 'Consulta indisponível.';
    return 'Sessões salvas: ${_sessoes.length}';
  }

  Future<void> abrirFormulario({SessaoEstudo? sessao}) async {
    if (_ocupado || _carregando) return;
    setState(() => _ocupado = true);
    bool gravou = false;
    try {
      final resultado = await Navigator.push<SessaoEstudo>(
        context,
        MaterialPageRoute<SessaoEstudo>(
          builder: (context) => TelaFormulario(sessao: sessao),
        ),
      );
      if (!mounted || resultado == null) return;
      final int afetadas;
      if (sessao == null) {
        await _banco.cadastrar(resultado);
        afetadas = 1;
      } else {
        if (resultado.id != sessao.id) {
          throw StateError('Identidade alterada no formulário.');
        }
        afetadas = await _banco.atualizar(resultado);
      }
      if (!mounted) return;
      if (afetadas != 1) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Registro não encontrado. A lista será consultada.')),
        );
        await carregarSessoes();
        return;
      }
      gravou = true;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(sessao == null
            ? 'Sessão cadastrada.'
            : 'Sessão atualizada.')),
      );
      await carregarSessoes();
    } catch (erro) {
      debugPrint('Falha ao salvar sessão: $erro');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(gravou
            ? 'Sessão salva. Use Consultar para atualizar a lista.'
            : 'Não foi possível salvar a alteração. Abra o formulário e tente novamente.')),
      );
    } finally {
      if (mounted) {
        setState(() => _ocupado = false);
      }
    }
  }

  Future<void> excluirSessao(SessaoEstudo sessao) async {
    if (_ocupado || _carregando) return;
    final id = sessao.id;
    if (id == null) return;
    setState(() => _ocupado = true);
    bool excluiu = false;
    try {
      final confirmou = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Excluir sessão?'),
          content: Text('Remover ID $id: ${sessao.tema}? Esta ação não tem desfazer.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop<bool>(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.pop<bool>(dialogContext, true),
              child: const Text('Excluir'),
            ),
          ],
        ),
      );
      if (!mounted || confirmou != true) return;
      final afetadas = await _banco.excluir(id);
      excluiu = afetadas == 1;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(excluiu
            ? 'Sessão excluída.'
            : 'Registro não encontrado. A lista será consultada.')),
      );
      await carregarSessoes();
    } catch (erro) {
      debugPrint('Falha ao excluir sessão: $erro');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(excluiu
            ? 'Exclusão concluída. Use Consultar para atualizar a lista.'
            : 'Não foi possível excluir. Consulte antes de tentar novamente.')),
      );
    } finally {
      if (mounted) {
        setState(() => _ocupado = false);
      }
    }
  }

  Widget conteudoSessoes() {
    if (_carregando) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_erro != null) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_erro!),
              TextButton(
                onPressed: _ocupado ? null : carregarSessoes,
                child: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
      );
    }
    if (_sessoes.isEmpty) {
      return const Center(
        child: Text('Nenhuma sessão salva. Toque em Cadastrar.'),
      );
    }
    return ListView.builder(
      itemCount: _sessoes.length,
      itemBuilder: (context, index) {
        final sessao = _sessoes[index];
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ListTile(
                  leading: CircleAvatar(child: Text('${sessao.id}')),
                  title: Text(sessao.tema),
                  subtitle: Text('${sessao.minutos} minutos\n'
                      '${sessao.observacao.isEmpty ? "Sem observação" : sessao.observacao}'),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    TextButton.icon(
                      onPressed: _ocupado || _carregando
                          ? null
                          : () => abrirFormulario(sessao: sessao),
                      icon: const Icon(Icons.edit),
                      label: const Text('Editar'),
                    ),
                    TextButton.icon(
                      onPressed: _ocupado || _carregando
                          ? null
                          : () => excluirSessao(sessao),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Excluir'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Minhas sessões'),
        actions: [
          TextButton.icon(
            onPressed: _ocupado || _carregando ? null : carregarSessoes,
            icon: const Icon(Icons.refresh),
            label: const Text('Consultar'),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(resumoSessao()),
            ),
            Expanded(child: conteudoSessoes()),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _ocupado || _carregando ? null : abrirFormulario,
        tooltip: 'Nova sessão',
        icon: const Icon(Icons.add),
        label: const Text('Cadastrar'),
      ),
    );
  }
}

class TelaFormulario extends StatefulWidget {
  final SessaoEstudo? sessao;

  const TelaFormulario({super.key, this.sessao});

  @override
  State<TelaFormulario> createState() => _TelaFormularioState();
}

class _TelaFormularioState extends State<TelaFormulario> {
  final _formKey = GlobalKey<FormState>();
  final _temaController = TextEditingController();
  final _minutosController = TextEditingController();
  final _observacaoController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final sessao = widget.sessao;
    if (sessao != null) {
      _temaController.text = sessao.tema;
      _minutosController.text = sessao.minutos.toString();
      _observacaoController.text = sessao.observacao;
    }
  }

  @override
  void dispose() {
    _temaController.dispose();
    _minutosController.dispose();
    _observacaoController.dispose();
    super.dispose();
  }


  void confirmar() {
    final valido = _formKey.currentState?.validate() ?? false;
    if (!valido) return;
    final minutos = int.tryParse(_minutosController.text.trim());
    if (minutos == null) return;
    final sessao = SessaoEstudo(
      id: widget.sessao?.id,
      tema: _temaController.text.trim(),
      minutos: minutos,
      observacao: _observacaoController.text.trim(),
    );
    Navigator.pop<SessaoEstudo>(context, sessao);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.sessao == null ? 'Nova sessão' : 'Editar sessão'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Planeje uma sessão de estudo.'),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _temaController,
                  validator: (value) {
                    final tema = (value ?? '').trim();
                    if (tema.isEmpty) {
                      return 'Informe o tema do estudo.';
                    }
                    if (tema.length < 3) {
                      return 'Use pelo menos 3 caracteres no tema.';
                    }
                    return null;
                  },
                  decoration: const InputDecoration(
                    labelText: 'Tema do estudo',
                    hintText: 'Ex.: Revisar Form e validação',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _minutosController,
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    final texto = (value ?? '').trim();
                    if (texto.isEmpty) {
                      return 'Informe a duração.';
                    }
                    final minutos = int.tryParse(texto);
                    if (minutos == null) {
                      return 'Digite um número inteiro de minutos.';
                    }
                    if (minutos < 1 || minutos > 240) {
                      return 'Use uma duração de 1 a 240 minutos.';
                    }
                    return null;
                  },
                  decoration: const InputDecoration(
                    labelText: 'Duração em minutos',
                    hintText: 'De 1 a 240',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _observacaoController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Observação (opcional)',
                    hintText: 'Ex.: Resolver os exemplos da aula',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: confirmar,
                  child: const Text('Confirmar sessão'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
