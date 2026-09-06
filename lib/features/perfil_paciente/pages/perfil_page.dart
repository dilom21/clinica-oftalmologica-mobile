import 'package:flutter/material.dart';

import '../../../core/storage/token_storage.dart';
import '../models/mi_perfil_paciente.dart';
import '../services/paciente_service.dart';
import '../../authentication_security/pages/login/login_page.dart';

/// Perfil del paciente autenticado con capacidad de consulta y edición.
///
/// Implementa CU08: Gestionar perfil propio.
/// Permite actualizar datos personales y de contacto autorizados.
class PerfilPage extends StatefulWidget {
  const PerfilPage({super.key});

  @override
  State<PerfilPage> createState() => _PerfilPageState();
}

class _PerfilPageState extends State<PerfilPage>
    with TickerProviderStateMixin {
  // Colores de la identidad Visión Clara.
  static const Color _azulProfundo = Color(0xFF0D47A1);
  static const Color _azulPrincipal = Color(0xFF1976D2);
  static const Color _verdeActivo = Color(0xFF2E7D32);
  static const Color _rojoSalida = Color(0xFFD32F2F);

  final PacienteService _pacienteService = PacienteService();
  final _formKey = GlobalKey<FormState>();

  // --- Controladores de texto para edición ---
  final _nombresController = TextEditingController();
  final _apellidosController = TextEditingController();
  final _fechaController = TextEditingController();
  final _telefonoController = TextEditingController();
  final _contactoEmergenciaController = TextEditingController();
  final _direccionController = TextEditingController();

  // --- Estado ---
  MiPerfilPaciente? _perfil;
  String? _error;
  bool _cargando = true;
  bool _editando = false;
  bool _guardando = false;
  DateTime? _fechaNacimiento;
  String? _sexo;

  // Animaciones de entrada.
  late final AnimationController _animacion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  );

  late final Animation<double> _cabeceraEntrance = CurvedAnimation(
    parent: _animacion,
    curve: const Interval(0.0, 0.35, curve: Curves.easeOutCubic),
  );
  late final Animation<double> _avatarEntrance = CurvedAnimation(
    parent: _animacion,
    curve: const Interval(0.05, 0.4, curve: Curves.easeOutCubic),
  );
  late final Animation<double> _datosEntrance = CurvedAnimation(
    parent: _animacion,
    curve: const Interval(0.25, 0.55, curve: Curves.easeOutCubic),
  );
  late final Animation<double> _logoutEntrance = CurvedAnimation(
    parent: _animacion,
    curve: const Interval(0.5, 0.75, curve: Curves.easeOutCubic),
  );
  late final Animation<double> _cuentaEntrance = CurvedAnimation(
    parent: _animacion,
    curve: const Interval(0.68, 0.9, curve: Curves.easeOutCubic),
  );
  late final Animation<double> _contactoEntrance = CurvedAnimation(
    parent: _animacion,
    curve: const Interval(0.8, 1.0, curve: Curves.easeOutCubic),
  );

  late final Animation<double> _avatarScale =
      Tween<double>(begin: 0.95, end: 1.0).animate(_avatarEntrance);

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _animacion.dispose();
    _nombresController.dispose();
    _apellidosController.dispose();
    _fechaController.dispose();
    _telefonoController.dispose();
    _contactoEmergenciaController.dispose();
    _direccionController.dispose();
    super.dispose();
  }

  /// Carga controlada del perfil.
  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
      _perfil = null;
    });

    try {
      final perfil = await _pacienteService.obtenerMiPerfil();

      if (!mounted) return;
      setState(() {
        _perfil = perfil;
        _cargando = false;
      });
      _animacion.forward(from: 0);
    } on PacienteException catch (error) {
      if (!mounted) return;
      if (error.statusCode == 401) {
        await _borrarSesionYSalir();
        return;
      }
      setState(() {
        _error = error.message;
        _cargando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Ocurrió un error inesperado. Inténtalo de nuevo.';
        _cargando = false;
      });
    }
  }

  /// Activa el modo edición y precarga los datos.
  void _iniciarEdicion() {
    if (_perfil == null) return;
    setState(() {
      _editando = true;
      _nombresController.text = _perfil!.nombres;
      _apellidosController.text = _perfil!.apellidos;
      _fechaNacimiento = _perfil!.fechaNacimiento;
      _fechaController.text = _formatoFecha(_perfil!.fechaNacimiento);
      _sexo = _perfil!.sexo;
      _telefonoController.text = _perfil!.telefono ?? '';
      _contactoEmergenciaController.text = _perfil!.contactoEmergencia ?? '';
      _direccionController.text = _perfil!.direccion ?? '';
    });
  }

  /// Cancela la edición y vuelve a la vista de solo lectura.
  void _cancelarEdicion() {
    setState(() {
      _editando = false;
    });
  }

  /// Envía la actualización al backend.
  Future<void> _guardarCambios() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _guardando = true);

    final request = ActualizarPerfilRequest(
      nombres: _nombresController.text.trim(),
      apellidos: _apellidosController.text.trim(),
      fechaNacimiento: _fechaNacimiento!,
      sexo: _sexo!,
      telefono: _vacioANull(_telefonoController.text),
      contactoEmergencia: _vacioANull(_contactoEmergenciaController.text),
      direccion: _vacioANull(_direccionController.text),
    );

    try {
      final perfilActualizado = await _pacienteService.actualizarPerfilPropio(request);

      if (!mounted) return;
      setState(() {
        _perfil = perfilActualizado;
        _editando = false;
        _guardando = false;
      });
      _mostrarSnack('Perfil actualizado correctamente', esExito: true);
    } on PacienteException catch (e) {
      if (!mounted) return;
      setState(() => _guardando = false);
      _mostrarSnack(e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _guardando = false);
      _mostrarSnack('Ocurrió un error al guardar los cambios.');
    }
  }

  String? _vacioANull(String valor) {
    final texto = valor.trim();
    return texto.isEmpty ? null : texto;
  }

  void _mostrarSnack(String mensaje, {bool esExito = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje),
        backgroundColor: esExito ? _verdeActivo : _rojoSalida,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _seleccionarFecha() async {
    final now = DateTime.now();
    final fechaElegida = await showDatePicker(
      context: context,
      initialDate: _fechaNacimiento ?? DateTime(now.year - 20, now.month, now.day),
      firstDate: DateTime(1900),
      lastDate: DateTime(now.year, now.month, now.day),
      helpText: 'Selecciona tu fecha de nacimiento',
    );

    if (fechaElegida != null && mounted) {
      setState(() {
        _fechaNacimiento = fechaElegida;
        _fechaController.text = _formatoFecha(fechaElegida);
      });
    }
  }

  Future<void> _borrarSesionYSalir() async {
    final storage = TokenStorage();
    await storage.deleteToken();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  Future<void> _cerrarSesion() async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.logout, color: _rojoSalida, size: 40),
        title: const Text('¿Cerrar sesión?'),
        content: const Text('¿Estás seguro de que deseas cerrar tu sesión?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(backgroundColor: _rojoSalida),
            child: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );

    if (confirmado == true && mounted) {
      await _borrarSesionYSalir();
    }
  }

  // --- Presentación ---

  static String _formatoFecha(DateTime fecha) {
    final dia = fecha.day.toString().padLeft(2, '0');
    final mes = fecha.month.toString().padLeft(2, '0');
    return '$dia/$mes/${fecha.year}';
  }

  static String _labelSexo(String? sexo) {
    if (sexo == 'M') return 'Masculino';
    if (sexo == 'F') return 'Femenino';
    return (sexo?.isEmpty ?? true) ? 'No registrado' : sexo!;
  }

  static String _textoCampo(String? valor) {
    final texto = valor?.trim() ?? '';
    return texto.isEmpty ? 'No registrado' : texto;
  }

  // --- Construcción de UI ---

  Widget _bloqueAnimado({required Animation<double> animation, required Widget child}) {
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero).animate(animation),
        child: child,
      ),
    );
  }

  Widget _construirContenido() {
    if (_cargando) return _buildCargando();
    if (_error != null || _perfil == null) return _buildError();
    return _editando ? _buildFormularioEdicion() : _buildVistaPerfil(_perfil!);
  }

  Widget _buildCargando() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(strokeWidth: 2.6, color: _azulPrincipal),
          SizedBox(height: 16),
          Text('Cargando perfil…', style: TextStyle(color: Color(0xFF5C6F80))),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 44, color: Colors.orange),
          const SizedBox(height: 14),
          Text('No se pudo cargar tu perfil',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: _azulProfundo)),
          const SizedBox(height: 8),
          Text(_error ?? 'Inténtalo de nuevo.', textAlign: TextAlign.center),
          const SizedBox(height: 20),
          ElevatedButton(onPressed: _cargar, child: const Text('Reintentar')),
        ],
      ),
    );
  }

  /// Vista de solo lectura del perfil.
  Widget _buildVistaPerfil(MiPerfilPaciente perfil) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _bloqueAnimado(
            animation: _cabeceraEntrance,
            child: Text('Mi Perfil', textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold, color: _azulProfundo)),
          ),
          const SizedBox(height: 26),
          _buildInfoBasica(perfil),
          const SizedBox(height: 24),
          _bloqueAnimado(
            animation: _logoutEntrance,
            child: _buildBotonActivarEdicion(),
          ),
          const SizedBox(height: 18),
          _bloqueAnimado(animation: _cuentaEntrance, child: _tarjetaCuenta(perfil)),
          const SizedBox(height: 18),
          _bloqueAnimado(animation: _contactoEntrance, child: _tarjetaContacto(perfil)),
          const SizedBox(height: 26),
          _bloqueAnimado(animation: _logoutEntrance, child: _buildBotonCerrarSesion()),
        ],
      ),
    );
  }

  Widget _buildInfoBasica(MiPerfilPaciente perfil) {
    return Column(
      children: [
        FadeTransition(
          opacity: _avatarEntrance,
          child: ScaleTransition(
            scale: _avatarScale,
            child: Container(
              width: 104,
              height: 104,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(colors: [Color(0xFFD6ECFA), Color(0xFFB7E3F9)]),
                boxShadow: [BoxShadow(color: _azulPrincipal.withValues(alpha: 0.16), blurRadius: 18, offset: const Offset(0, 6))],
              ),
              child: const Icon(Icons.person_outline, size: 54, color: _azulProfundo),
            ),
          ),
        ),
        const SizedBox(height: 18),
        FadeTransition(
          opacity: _datosEntrance,
          child: Text(perfil.nombreCompleto, textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1B2B3A))),
        ),
        FadeTransition(
          opacity: _datosEntrance,
          child: Text(perfil.correo, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF5C6F80))),
        ),
        const SizedBox(height: 12),
        FadeTransition(
          opacity: _datosEntrance,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(color: const Color(0xFFD8ECFA), borderRadius: BorderRadius.circular(20)),
            child: const Text('Paciente', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _azulProfundo)),
          ),
        ),
      ],
    );
  }

  Widget _buildBotonActivarEdicion() {
    return OutlinedButton.icon(
      onPressed: _iniciarEdicion,
      icon: const Icon(Icons.edit_outlined),
      label: const Text('Editar mi información'),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        side: const BorderSide(color: _azulPrincipal, width: 1.2),
      ),
    );
  }

  /// Formulario de edición de datos.
  Widget _buildFormularioEdicion() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Editar Perfil', textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold, color: _azulProfundo)),
            const SizedBox(height: 24),
            _buildGrupoEdicion('Datos Personales', [
              _campoTexto(controller: _nombresController, label: 'Nombres', icon: Icons.person_outline),
              const SizedBox(height: 14),
              _campoTexto(controller: _apellidosController, label: 'Apellidos', icon: Icons.person_outline),
              const SizedBox(height: 14),
              _campoFecha(),
              const SizedBox(height: 14),
              _campoSexo(),
            ]),
            const SizedBox(height: 22),
            _buildGrupoEdicion('Contacto', [
              _campoTexto(controller: _telefonoController, label: 'Teléfono', icon: Icons.phone_outlined, keyboardType: TextInputType.phone),
              const SizedBox(height: 14),
              _campoTexto(controller: _contactoEmergenciaController, label: 'Contacto Emergencia', icon: Icons.emergency_outlined, keyboardType: TextInputType.phone),
              const SizedBox(height: 14),
              _campoTexto(controller: _direccionController, label: 'Dirección', icon: Icons.location_on_outlined),
            ]),
            const SizedBox(height: 30),
            if (_guardando)
              const Center(child: CircularProgressIndicator(color: _azulPrincipal))
            else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _cancelarEdicion,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: const Text('Cancelar'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: FilledButton(
                      onPressed: _guardarCambios,
                      style: FilledButton.styleFrom(
                        backgroundColor: _azulPrincipal,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: const Text('Guardar'),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildGrupoEdicion(String titulo, List<Widget> campos) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 6, bottom: 8),
          child: Text(titulo.toUpperCase(),
            style: const TextStyle(color: _azulProfundo, fontSize: 13, fontWeight: FontWeight.bold)),
        ),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(children: campos),
        ),
      ],
    );
  }

  Widget _campoTexto({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        filled: true,
        fillColor: Colors.grey.shade50,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.grey.shade300)),
      ),
      validator: (v) => (v == null || v.trim().isEmpty) ? 'El campo es obligatorio' : null,
    );
  }

  Widget _campoFecha() {
    return TextFormField(
      controller: _fechaController,
      readOnly: true,
      onTap: _seleccionarFecha,
      decoration: InputDecoration(
        labelText: 'Fecha de nacimiento',
        prefixIcon: const Icon(Icons.cake_outlined),
        suffixIcon: const Icon(Icons.calendar_today_outlined, size: 20),
        filled: true,
        fillColor: Colors.grey.shade50,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      ),
      validator: (v) => _fechaNacimiento == null ? 'Selecciona una fecha' : null,
    );
  }

  Widget _campoSexo() {
    return DropdownButtonFormField<String>(
      initialValue: _sexo,
      decoration: InputDecoration(
        labelText: 'Sexo',
        prefixIcon: const Icon(Icons.wc_outlined),
        filled: true,
        fillColor: Colors.grey.shade50,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      ),
      items: const [
        DropdownMenuItem(value: 'M', child: Text('Masculino')),
        DropdownMenuItem(value: 'F', child: Text('Femenino')),
      ],
      onChanged: (v) => setState(() => _sexo = v),
      validator: (v) => v == null ? 'Selecciona una opción' : null,
    );
  }

  Widget _tarjetaCuenta(MiPerfilPaciente perfil) {
    return _TarjetaSeccion(
      titulo: 'Información de tu cuenta',
      hijos: [
        _FilaInfo(label: 'CI', value: perfil.ci),
        const Divider(color: Color(0xFFE4EDF4)),
        _FilaInfo(label: 'Fecha de nacimiento', value: _formatoFecha(perfil.fechaNacimiento)),
        const Divider(color: Color(0xFFE4EDF4)),
        _FilaInfo(label: 'Sexo', value: _labelSexo(perfil.sexo)),
        const Divider(color: Color(0xFFE4EDF4)),
        _FilaInfo(label: 'Estado', value: perfil.estado ? 'Activo' : 'Inactivo', colorValor: perfil.estado ? _verdeActivo : _rojoSalida),
      ],
    );
  }

  Widget _tarjetaContacto(MiPerfilPaciente perfil) {
    return _TarjetaSeccion(
      titulo: 'Información de contacto',
      hijos: [
        _FilaInfo(label: 'Teléfono', value: _textoCampo(perfil.telefono)),
        const Divider(color: Color(0xFFE4EDF4)),
        _FilaInfo(label: 'Contacto de emergencia', value: _textoCampo(perfil.contactoEmergencia)),
        const Divider(color: Color(0xFFE4EDF4)),
        _FilaInfo(label: 'Dirección', value: _textoCampo(perfil.direccion)),
      ],
    );
  }

  Widget _buildBotonCerrarSesion() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFFEBEE),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFFFCDD2), width: 1.2),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _cerrarSesion,
          borderRadius: BorderRadius.circular(22),
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.logout, size: 20, color: _rojoSalida),
                SizedBox(width: 10),
                Text('Cerrar sesión', style: TextStyle(color: _rojoSalida, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: _FondoPerfil()),
          SafeArea(child: _construirContenido()),
        ],
      ),
    );
  }
}

class _FondoPerfil extends StatelessWidget {
  const _FondoPerfil();
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFF4F9FF), Color(0xFFE3F1FC), Color(0xFFD0EAF8)],
              ),
            ),
          ),
        ),
        Positioned(
          top: -80, right: -90,
          child: _CirculoDecorativo(size: 280, color: const Color(0xFF1976D2).withValues(alpha: 0.09)),
        ),
        Positioned(
          bottom: -70, left: -90,
          child: _CirculoDecorativo(size: 260, color: const Color(0xFF4FC3F7).withValues(alpha: 0.10)),
        ),
      ],
    );
  }
}

class _CirculoDecorativo extends StatelessWidget {
  final double size;
  final Color color;
  const _CirculoDecorativo({required this.size, required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)])),
    );
  }
}

class _TarjetaSeccion extends StatelessWidget {
  const _TarjetaSeccion({required this.titulo, required this.hijos});
  final String titulo;
  final List<Widget> hijos;
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [BoxShadow(color: const Color(0xFF1976D2).withValues(alpha: 0.08), blurRadius: 16, offset: const Offset(0, 6))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(titulo, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0D47A1))),
            const SizedBox(height: 12),
            ...hijos,
          ],
        ),
      ),
    );
  }
}

class _FilaInfo extends StatelessWidget {
  const _FilaInfo({required this.label, required this.value, this.colorValor});
  final String label;
  final String value;
  final Color? colorValor;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 5, child: Text(label, style: const TextStyle(color: Color(0xFF5C6F80)))),
          const SizedBox(width: 12),
          Expanded(flex: 6, child: Text(value, textAlign: TextAlign.right,
            style: TextStyle(color: colorValor ?? const Color(0xFF1B2B3A), fontWeight: colorValor != null ? FontWeight.w600 : null))),
        ],
      ),
    );
  }
}
