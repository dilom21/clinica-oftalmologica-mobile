import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/auth_models.dart';
import '../../services/auth_service.dart';

/// Pantalla de registro de paciente de la app móvil Visión Clara.
///
/// Envía los datos a `POST /seguridad/registro-paciente`. El backend decide si
/// el paciente ya existía o debe crearse.
class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage>
    with TickerProviderStateMixin {
  // Color de la identidad Visión Clara.
  static const Color _azulProfundo = Color(0xFF0D47A1);

  final _formKey = GlobalKey<FormState>();

  // --- Controladores de texto ---
  final _ciController = TextEditingController();
  final _nombresController = TextEditingController();
  final _apellidosController = TextEditingController();
  final _fechaController = TextEditingController();
  final _telefonoController = TextEditingController();
  final _contactoEmergenciaController = TextEditingController();
  final _direccionController = TextEditingController();
  final _correoController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  // --- Estado del formulario ---
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;
  DateTime? _fechaNacimiento;
  String? _sexo;

  final AuthService _authService = AuthService();

  // Controla la animación de entrada escalonada.
  late final AnimationController _entranceController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  );

  // Controla la microanimación del botón crear cuenta.
  late final AnimationController _buttonController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );

  late final Animation<double> _headerEntrance = CurvedAnimation(
    parent: _entranceController,
    curve: const Interval(0.0, 0.25, curve: Curves.easeOutCubic),
  );
  late final Animation<double> _personalEntrance = CurvedAnimation(
    parent: _entranceController,
    curve: const Interval(0.18, 0.42, curve: Curves.easeOutCubic),
  );
  late final Animation<double> _contactEntrance = CurvedAnimation(
    parent: _entranceController,
    curve: const Interval(0.38, 0.62, curve: Curves.easeOutCubic),
  );
  late final Animation<double> _accessEntrance = CurvedAnimation(
    parent: _entranceController,
    curve: const Interval(0.58, 0.82, curve: Curves.easeOutCubic),
  );
  late final Animation<double> _buttonEntrance = CurvedAnimation(
    parent: _entranceController,
    curve: const Interval(0.8, 1.0, curve: Curves.easeOutCubic),
  );

  late final Animation<double> _buttonScale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween<double>(begin: 1.0, end: 0.98)
          .chain(CurveTween(curve: Curves.easeOut)),
      weight: 50,
    ),
    TweenSequenceItem(
      tween: Tween<double>(begin: 0.98, end: 1.0)
          .chain(CurveTween(curve: Curves.easeOut)),
      weight: 50,
    ),
  ]).animate(_buttonController);

  @override
  void initState() {
    super.initState();
    _entranceController.forward();
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _buttonController.dispose();
    _ciController.dispose();
    _nombresController.dispose();
    _apellidosController.dispose();
    _fechaController.dispose();
    _telefonoController.dispose();
    _contactoEmergenciaController.dispose();
    _direccionController.dispose();
    _correoController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _togglePassword() {
    setState(() => _obscurePassword = !_obscurePassword);
  }

  void _toggleConfirmPassword() {
    setState(() => _obscureConfirmPassword = !_obscureConfirmPassword);
  }

  /// Abre el selector de fecha y muestra la fecha en formato dd/MM/yyyy.
  Future<void> _seleccionarFecha() async {
    final now = DateTime.now();
    final fechaElegida = await showDatePicker(
      context: context,
      initialDate:
          _fechaNacimiento ?? DateTime(now.year - 20, now.month, now.day),
      firstDate: DateTime(1900),
      lastDate: DateTime(now.year, now.month, now.day),
      helpText: 'Selecciona tu fecha de nacimiento',
      cancelText: 'Cancelar',
      confirmText: 'Aceptar',
    );

    if (fechaElegida != null && mounted) {
      setState(() {
        _fechaNacimiento = fechaElegida;
        _fechaController.text = _formatoFecha(fechaElegida);
      });
    }
  }

  /// Convierte una fecha a formato amigable dd/MM/yyyy.
  String _formatoFecha(DateTime fecha) {
    final dia = fecha.day.toString().padLeft(2, '0');
    final mes = fecha.month.toString().padLeft(2, '0');
    return '$dia/$mes/${fecha.year}';
  }

  /// Decoración común para todos los campos del formulario.
  InputDecoration _decoracion({
    required IconData icon,
    required String label,
    String? hint,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.9),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.grey.shade300, width: 1.2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF1E88E5), width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.red.shade300, width: 1.2),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.red.shade400, width: 2),
      ),
    );
  }

  /// Valida el formulario y envía la petición de registro a FastAPI.
  Future<void> _crearCuenta() async {
    if (_isLoading) {
      return;
    }

    // Microanimación de escala al presionar el botón.
    _buttonController.forward(from: 0);

    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final request = RegistroPacienteRequest(
      ci: _ciController.text.trim(),
      nombres: _nombresController.text.trim(),
      apellidos: _apellidosController.text.trim(),
      fechaNacimiento: _fechaNacimiento!,
      sexo: _sexo!,
      telefono: _telefonoController.text.trim(),
      contactoEmergencia: _vacioANull(_contactoEmergenciaController.text),
      direccion: _vacioANull(_direccionController.text),
      correo: _correoController.text.trim(),
      password: _passwordController.text,
    );

    try {
      await _authService.registrarPaciente(request);

      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });

      // Confirmación elegante; después se regresa al Login con el correo.
      await _mostrarConfirmacion();

      if (!mounted) return;
      Navigator.of(context).pop(_correoController.text.trim());
    } on AuthException catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      _mostrarError(error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      _mostrarError('Ocurrió un error inesperado. Inténtalo de nuevo.');
    }
  }

  /// Convierte un texto vacío en `null` para los campos opcionales.
  String? _vacioANull(String valor) {
    final texto = valor.trim();
    return texto.isEmpty ? null : texto;
  }

  /// Diálogo de éxito tras un registro correcto.
  Future<void> _mostrarConfirmacion() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(
          Icons.check_circle_outline,
          color: Color(0xFF2E7D32),
          size: 48,
        ),
        title: const Text('Cuenta creada correctamente'),
        content: const Text(
          'Ya puedes iniciar sesión con tu correo y contraseña.',
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF1976D2),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text('Ir a iniciar sesión'),
          ),
        ],
      ),
    );
  }

  /// Muestra un error entendible al usuario.
  void _mostrarError(String mensaje) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(mensaje),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
  }

  String? _validarObligatorio(String? valor, String campo) {
    if (valor == null || valor.trim().isEmpty) {
      return 'El campo $campo es obligatorio';
    }
    return null;
  }

  String? _validarCorreo(String? valor) {
    final correo = valor?.trim() ?? '';
    if (correo.isEmpty) {
      return 'El correo electrónico es obligatorio';
    }
    final emailRegex = RegExp(r'^[\w\.-]+@[\w\.-]+\.\w+$');
    if (!emailRegex.hasMatch(correo)) {
      return 'Ingresa un correo electrónico válido';
    }
    return null;
  }

  String? _validarPassword(String? valor) {
    final password = valor ?? '';
    if (password.isEmpty) {
      return 'La contraseña es obligatoria';
    }
    if (password.length < 8) {
      return 'La contraseña debe tener al menos 8 caracteres';
    }
    if (!RegExp(r'[A-Z]').hasMatch(password)) {
      return 'Debe incluir una letra mayúscula';
    }
    if (!RegExp(r'[a-z]').hasMatch(password)) {
      return 'Debe incluir una letra minúscula';
    }
    if (!RegExp(r'[0-9]').hasMatch(password)) {
      return 'Debe incluir un número';
    }
    if (!RegExp(r'[!@#$%^&*?_\-]').hasMatch(password)) {
      return 'Debe incluir un carácter especial';
    }
    return null;
  }

  String? _validarConfirmPassword(String? valor) {
    if (valor == null || valor.isEmpty) {
      return 'Confirma tu contraseña';
    }
    if (valor != _passwordController.text) {
      return 'Las contraseñas no coinciden';
    }
    return null;
  }

  /// Constructor de campos de texto reutilizable.
  Widget _campoTexto({
    required TextEditingController controller,
    required IconData icon,
    required String label,
    required String? Function(String?) validator,
    String? hint,
    TextInputType? keyboardType,
    List<TextInputFormatter>? formatters,
    bool obscureText = false,
    Widget? suffixIcon,
    String? helperText,
    TextInputAction textInputAction = TextInputAction.next,
    bool autocorrect = true,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: formatters,
      obscureText: obscureText,
      textInputAction: textInputAction,
      autocorrect: autocorrect,
      validator: validator,
      decoration: _decoracion(
        icon: icon,
        label: label,
        hint: hint,
        suffixIcon: suffixIcon,
      ).copyWith(helperText: helperText),
    );
  }

  /// Campo de fecha de nacimiento con selector visual.
  Widget _campoFecha() {
    return TextFormField(
      controller: _fechaController,
      readOnly: true,
      onTap: _isLoading ? null : _seleccionarFecha,
      decoration: _decoracion(
        icon: Icons.cake_outlined,
        label: 'Fecha de nacimiento',
        hint: 'dd/mm/aaaa',
        suffixIcon: const Icon(Icons.calendar_today_outlined),
      ),
      validator: (_) => _fechaNacimiento == null
          ? 'Selecciona tu fecha de nacimiento'
          : null,
    );
  }

  /// Campo de sexo (valores compatibles con FastAPI: M/F).
  Widget _campoSexo() {
    return DropdownButtonFormField<String>(
      initialValue: _sexo,
      isExpanded: true,
      decoration: _decoracion(
        icon: Icons.wc_outlined,
        label: 'Sexo',
        hint: 'Selecciona una opción',
      ),
      items: const [
        DropdownMenuItem(value: 'M', child: Text('Masculino')),
        DropdownMenuItem(value: 'F', child: Text('Femenino')),
      ],
      onChanged: _isLoading
          ? null
          : (value) => setState(() => _sexo = value),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Selecciona tu sexo';
        }
        return null;
      },
    );
  }

  /// Agrupa campos bajo un título con un contenedor suave.
  Widget _grupo(String titulo, List<Widget> campos) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 6, bottom: 10),
          child: Text(
            titulo.toUpperCase(),
            style: const TextStyle(
              color: Color(0xFF0D47A1),
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
        ),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.78),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.grey.shade200, width: 1),
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: campos,
            ),
          ),
        ),
      ],
    );
  }

  /// Separador vertical entre campos.
  Widget _espacio([double alto = 14]) => SizedBox(height: alto);

  Widget _seccionDatosPersonales() {
    return _grupo(
      'Datos personales',
      [
        _campoTexto(
          controller: _ciController,
          icon: Icons.badge_outlined,
          label: 'Carnet de identidad',
          hint: 'Ej. 12345678',
          keyboardType: TextInputType.number,
          formatters: [FilteringTextInputFormatter.digitsOnly],
          validator: (v) => _validarObligatorio(v, 'CI'),
        ),
        _espacio(),
        _campoTexto(
          controller: _nombresController,
          icon: Icons.person_outline,
          label: 'Nombres',
          hint: 'Escribe tus nombres',
          validator: (v) => _validarObligatorio(v, 'nombres'),
        ),
        _espacio(),
        _campoTexto(
          controller: _apellidosController,
          icon: Icons.person_outline,
          label: 'Apellidos',
          hint: 'Escribe tus apellidos',
          validator: (v) => _validarObligatorio(v, 'apellidos'),
        ),
        _espacio(),
        _campoFecha(),
        _espacio(),
        _campoSexo(),
      ],
    );
  }

  Widget _seccionContacto() {
    return _grupo(
      'Datos de contacto',
      [
        _campoTexto(
          controller: _telefonoController,
          icon: Icons.phone_outlined,
          label: 'Teléfono',
          hint: 'Ej. +59170000000',
          keyboardType: TextInputType.phone,
          validator: (v) => _validarObligatorio(v, 'teléfono'),
        ),
        _espacio(),
        _campoTexto(
          controller: _contactoEmergenciaController,
          icon: Icons.emergency_outlined,
          label: 'Contacto de emergencia',
          hint: 'Ej. +59171111111 (opcional)',
          keyboardType: TextInputType.phone,
          validator: (_) => null,
        ),
        _espacio(),
        _campoTexto(
          controller: _direccionController,
          icon: Icons.location_on_outlined,
          label: 'Dirección',
          hint: 'Ej. Av. Ejemplo 123 (opcional)',
          validator: (_) => null,
        ),
      ],
    );
  }

  Widget _seccionAcceso() {
    return _grupo(
      'Datos de acceso',
      [
        _campoTexto(
          controller: _correoController,
          icon: Icons.email_outlined,
          label: 'Correo electrónico',
          hint: 'ejemplo@correo.com',
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autocorrect: false,
          validator: _validarCorreo,
        ),
        _espacio(),
        _campoTexto(
          controller: _passwordController,
          icon: Icons.lock_outline,
          label: 'Contraseña',
          hint: 'Crea una contraseña segura',
          obscureText: _obscurePassword,
          textInputAction: TextInputAction.next,
          suffixIcon: IconButton(
            onPressed: _togglePassword,
            icon: Icon(
              _obscurePassword
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
            ),
          ),
          helperText:
              'Debe incluir mayúscula, minúscula, número y carácter especial.',
          validator: _validarPassword,
        ),
        _espacio(),
        _campoTexto(
          controller: _confirmPasswordController,
          icon: Icons.lock_outline,
          label: 'Confirmar contraseña',
          obscureText: _obscureConfirmPassword,
          textInputAction: TextInputAction.done,
          suffixIcon: IconButton(
            onPressed: _toggleConfirmPassword,
            icon: Icon(
              _obscureConfirmPassword
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
            ),
          ),
          validator: _validarConfirmPassword,
        ),
      ],
    );
  }

  /// Envuelve un bloque con fade + slide para la entrada escalonada.
  Widget _bloqueAnimado({
    required Animation<double> animation,
    required Widget child,
  }) {
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.06),
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
    );
  }

  /// Cabecera: botón atrás, logo pequeño y textos de bienvenida.
  Widget _buildHeader() {
    return FadeTransition(
      opacity: _headerEntrance,
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.7),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                onPressed: _isLoading
                    ? null
                    : () => Navigator.of(context).maybePop(),
                icon: const Icon(
                  Icons.arrow_back_ios_new,
                  size: 20,
                  color: Color(0xFF0D47A1),
                ),
                tooltip: 'Volver',
              ),
            ),
          ),
          const SizedBox(height: 8),
          Image.asset(
            'assets/images/logo_vision_clara.png',
            height: 72,
            fit: BoxFit.contain,
          ),
          const SizedBox(height: 12),
          Text(
            'Crear cuenta',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: _azulProfundo,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            'Regístrate para acceder a los servicios de Visión Clara',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF5C6F80),
                  height: 1.35,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            'Completa tus datos para continuar',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF7893A9),
                ),
          ),
        ],
      ),
    );
  }

  /// Botón principal "Crear cuenta" con microanimación de escala.
  Widget _buildBotonCrearCuenta() {
    return ScaleTransition(
      scale: _buttonScale,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [Color(0xFF1976D2), Color(0xFF4FC3F7)],
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF1976D2).withValues(alpha: 0.28),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _isLoading ? null : _crearCuenta,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: _isLoading
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.4,
                        ),
                      )
                    : const Text(
                        'Crear cuenta',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
              ),
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
          // Fondo degradado discreto y formas suaves.
          const Positioned.fill(child: _FondoRegistro()),

          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildHeader(),
                        const SizedBox(height: 22),
                        _bloqueAnimado(
                          animation: _personalEntrance,
                          child: _seccionDatosPersonales(),
                        ),
                        const SizedBox(height: 22),
                        _bloqueAnimado(
                          animation: _contactEntrance,
                          child: _seccionContacto(),
                        ),
                        const SizedBox(height: 22),
                        _bloqueAnimado(
                          animation: _accessEntrance,
                          child: _seccionAcceso(),
                        ),
                        const SizedBox(height: 28),
                        _bloqueAnimado(
                          animation: _buttonEntrance,
                          child: _buildBotonCrearCuenta(),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Al crear tu cuenta podrás acceder '
                          'a los servicios de Visión Clara.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: const Color(0xFF7893A9)),
                        ),
                        const SizedBox(height: 8),
                      ],
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

/// Fondo con degradado suave y formas abstractas (estilo del login).
class _FondoRegistro extends StatelessWidget {
  const _FondoRegistro();

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
                colors: [
                  Color(0xFFF4F9FF),
                  Color(0xFFE3F1FC),
                  Color(0xFFD0EAF8),
                ],
              ),
            ),
          ),
        ),

        // Forma grande azul en la parte superior derecha.
        Positioned(
          top: -70,
          right: -80,
          child: _FormaRegistro(
            size: 280,
            color: const Color(0xFF1976D2).withValues(alpha: 0.10),
          ),
        ),

        // Forma celeste abajo izquierda.
        Positioned(
          bottom: -70,
          left: -90,
          child: _FormaRegistro(
            size: 280,
            color: const Color(0xFF4FC3F7).withValues(alpha: 0.10),
          ),
        ),

        // Anillo tipo lente (guiño a la visión) arriba izquierda.
        Positioned(
          top: 160,
          left: -60,
          child: Container(
            width: 180,
            height: 180,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFF1976D2).withValues(alpha: 0.06),
                width: 20,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Forma circular con gradiente radial (luz suave).
class _FormaRegistro extends StatelessWidget {
  final double size;
  final Color color;

  const _FormaRegistro({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: const Alignment(0.3, -0.3),
          colors: [color, color.withValues(alpha: 0)],
        ),
      ),
    );
  }
}


