import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../models/auth_models.dart';
import '../../services/auth_service.dart';
import '../../../../core/storage/token_storage.dart';
import '../../../home/pages/main_navigation_page.dart';
import '../register/register_page.dart';

/// Pantalla de inicio de sesión de la aplicación
/// "Centro Oftalmológico Visión Clara".
///
/// Solo contiene:
/// - Interfaz de usuario moderna (fondo degradado, glassmorphism)
/// - Animación de entrada escalonada
/// - Movimiento lento del fondo decorativo
/// - Estado visual (mostrar/ocultar contraseña)
/// - Validaciones locales del formulario
/// - Estado de carga mientras se consulta FastAPI
///
/// NOTA: El login usa el endpoint exclusivo de pacientes
/// `POST /seguridad/login`. Con un login exitoso se guarda el JWT
/// (TokenStorage) y se navega a MainNavigationPage.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage>
    with TickerProviderStateMixin {
  // Controla el formulario y sus validaciones.
  final _formKey = GlobalKey<FormState>();

  // Controla el texto del campo de correo electrónico.
  final _emailController = TextEditingController();

  // Controla el texto del campo de contraseña.
  final _passwordController = TextEditingController();

  // Indica si la contraseña se muestra en texto plano o se oculta.
  bool _obscurePassword = true;

  // Indica si hay una petición de login en curso.
  bool _isLoading = false;

  // Servicio que se comunica con el backend FastAPI.
  final AuthService _authService = AuthService();

  // Controla la animación de entrada escalonada (se ejecuta una sola vez).
  late final AnimationController _entranceController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  // Controla el movimiento lento y constante del fondo decorativo.
  late final AnimationController _backgroundController = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 9),
  )..repeat(reverse: true);

  // Controla la microanimación del botón (escala al presionar).
  late final AnimationController _buttonController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );

  // Animaciones de entrada para cada bloque de la pantalla.
  late final Animation<double> _backgroundEntrance = CurvedAnimation(
    parent: _entranceController,
    curve: const Interval(0.0, 0.2, curve: Curves.easeOutCubic),
  );
  late final Animation<double> _logoEntrance = CurvedAnimation(
    parent: _entranceController,
    curve: const Interval(0.1, 0.35, curve: Curves.easeOutCubic),
  );
  late final Animation<double> _cardEntrance = CurvedAnimation(
    parent: _entranceController,
    curve: const Interval(0.25, 0.55, curve: Curves.easeOutCubic),
  );
  late final Animation<double> _titleEntrance = CurvedAnimation(
    parent: _entranceController,
    curve: const Interval(0.32, 0.52, curve: Curves.easeOutCubic),
  );
  late final Animation<double> _fieldsEntrance = CurvedAnimation(
    parent: _entranceController,
    curve: const Interval(0.48, 0.7, curve: Curves.easeOutCubic),
  );
  late final Animation<double> _forgotEntrance = CurvedAnimation(
    parent: _entranceController,
    curve: const Interval(0.64, 0.8, curve: Curves.easeOutCubic),
  );
  late final Animation<double> _buttonEntrance = CurvedAnimation(
    parent: _entranceController,
    curve: const Interval(0.74, 0.94, curve: Curves.easeOutCubic),
  );

  // Entrada para el bloque "Crear cuenta nueva".
  late final Animation<double> _registerEntrance = CurvedAnimation(
    parent: _entranceController,
    curve: const Interval(0.86, 1.0, curve: Curves.easeOutCubic),
  );

  // El logo entra con una escala suave (0.92 -> 1.0).
  late final Animation<double> _logoScale =
      Tween<double>(begin: 0.92, end: 1.0).animate(_logoEntrance);

  // El botón reacciona al presionarlo: 1.0 -> 0.98 -> 1.0.
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

    // Inicia la animación de entrada al abrir la pantalla.
    _entranceController.forward();
  }

  @override
  void dispose() {
    // Libera los controladores de animación para evitar fugas de memoria.
    _entranceController.dispose();
    _backgroundController.dispose();
    _buttonController.dispose();

    // Libera los controladores de texto para evitar fugas de memoria.
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// Muestra u oculta la contraseña.
  void _togglePasswordVisibility() {
    setState(() {
      _obscurePassword = !_obscurePassword;
    });
  }

  /// Valida el formulario y, si es válido, inicia la petición de login.
  void _handleLogin() {
    // Microanimación de escala al presionar el botón.
    _buttonController.forward(from: 0);

    // Evita múltiples pulsaciones mientras hay una petición en curso.
    if (_isLoading) {
      return;
    }

    if (_formKey.currentState!.validate()) {
      _login();
    }
  }

  /// Llama a AuthService.loginPaciente() contra FastAPI.
  ///
  /// Con un login exitoso guarda el access_token con TokenStorage y navega a
  /// InicioPage eliminando LoginPage del historial.
  Future<void> _login() async {
    setState(() {
      _isLoading = true;
    });

    final request = LoginRequest(
      correo: _emailController.text.trim(),
      password: _passwordController.text,
    );

    try {
      final LoginResponse response =
          await _authService.loginPaciente(request);

      // Guardar el JWT de forma segura antes de navegar.
      await TokenStorage().saveToken(response.accessToken);

      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const MainNavigationPage()),
        (route) => false,
      );
    } on AuthException catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });

      _showMessage(error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });

      _showMessage('Ocurrió un error inesperado. Inténtalo de nuevo.');
    }
  }

  /// Navega a RegisterPage y, al volver, precarga el correo registrado.
  Future<void> _openRegister() async {
    final correoRegistrado = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => const RegisterPage(),
      ),
    );

    if (correoRegistrado != null &&
        correoRegistrado.isNotEmpty &&
        mounted) {
      _emailController.text = correoRegistrado;
    }
  }

  /// Muestra un SnackBar breve con el mensaje indicado.
  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
  }

  /// Envuelve un bloque con fade + slide para la entrada escalonada.
  Widget _buildAnimatedBlock({
    required Animation<double> animation,
    required Widget child,
  }) {
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.08),
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
    );
  }

  /// Bloque del logo e identidad visual (fade + escala).
  Widget _buildLogoBlock() {
    return FadeTransition(
      opacity: _logoEntrance,
      child: ScaleTransition(
        scale: _logoScale,
        child: Column(
          children: [
            // Logo oficial de la clínica.
            Image.asset(
              'assets/images/logo_vision_clara.png',
              height: 110,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 12),
            Text(
              'Visión Clara',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: const Color(0xFF0D47A1),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Centro Oftalmológico',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: const Color(0xFF547799),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Tarjeta central con efecto glassmorphism que contiene el formulario.
  Widget _buildGlassCard() {
    return _buildAnimatedBlock(
      animation: _cardEntrance,
      child: Container(
        // Contenedor exterior para que la sombra no sea recortada.
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF1976D2).withValues(alpha: 0.14),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            // Blur moderado para el efecto glassmorphism.
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.78),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.6),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Bloque: Título del formulario.
                  _buildAnimatedBlock(
                    animation: _titleEntrance,
                    child: Column(
                      children: [
                        Text(
                          'Iniciar sesión',
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Ingresa tus credenciales para continuar',
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(
                                color: const Color(0xFF5C6F80),
                              ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Bloque: Campos del formulario.
                  _buildAnimatedBlock(
                    animation: _fieldsEntrance,
                    child: Column(
                      children: [
                        _buildEmailField(),
                        const SizedBox(height: 16),
                        _buildPasswordField(),
                      ],
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Bloque: Enlace para recuperar contraseña.
                  _buildAnimatedBlock(
                    animation: _forgotEntrance,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () {
                          // TODO: Implementar recuperación de contraseña (CU03).
                        },
                        child: const Text('¿Olvidaste tu contraseña?'),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Bloque: Botón principal.
                  _buildAnimatedBlock(
                    animation: _buttonEntrance,
                    child: _buildLoginButton(),
                  ),

                  const SizedBox(height: 8),

                  // Bloque: separador "o" y acción secundaria.
                  _buildAnimatedBlock(
                    animation: _registerEntrance,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            const Expanded(
                              child: Divider(
                                color: Color(0xFFB9C9D6),
                                height: 1,
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              child: Text(
                                'o',
                                style: TextStyle(
                                  color: Colors.grey.shade500,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            const Expanded(
                              child: Divider(
                                color: Color(0xFFB9C9D6),
                                height: 1,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        _buildRegisterButton(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );  
  }

  /// Campo de correo electrónico.
  Widget _buildEmailField() {
    return TextFormField(
      controller: _emailController,
      keyboardType: TextInputType.emailAddress,
      textInputAction: TextInputAction.next,
      autocorrect: false,
      decoration: InputDecoration(
        labelText: 'Correo electrónico',
        hintText: 'ejemplo@correo.com',
        prefixIcon: const Icon(Icons.email_outlined),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.85),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        // Borde gris cuando no tiene foco.
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey.shade300, width: 1.2),
        ),
        // Borde azul cuando recibe foco (transición suave de Material).
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF1E88E5), width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: Theme.of(context).colorScheme.error,
            width: 1.2,
          ),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: Theme.of(context).colorScheme.error,
            width: 2,
          ),
        ),
      ),
      validator: (value) {
        final email = value?.trim() ?? '';

        if (email.isEmpty) {
          return 'El correo electrónico es obligatorio';
        }

        // Validación básica del formato del correo.
        final emailRegex = RegExp(r'^[\w\.-]+@[\w\.-]+\.\w+$');
        if (!emailRegex.hasMatch(email)) {
          return 'Ingresa un correo electrónico válido';
        }

        return null;
      },
    );
  }

  /// Campo de contraseña.
  Widget _buildPasswordField() {
    return TextFormField(
      controller: _passwordController,
      obscureText: _obscurePassword,
      textInputAction: TextInputAction.done,
      decoration: InputDecoration(
        labelText: 'Contraseña',
        prefixIcon: const Icon(Icons.lock_outline),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.85),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
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
          borderSide: BorderSide(
            color: Theme.of(context).colorScheme.error,
            width: 1.2,
          ),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: Theme.of(context).colorScheme.error,
            width: 2,
          ),
        ),
        // Botón del ojo con transición suave del icono.
        suffixIcon: IconButton(
          onPressed: _togglePasswordVisibility,
          icon: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: ScaleTransition(scale: animation, child: child),
              );
            },
            child: Icon(
              _obscurePassword
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              key: ValueKey(_obscurePassword),
            ),
          ),
          tooltip: _obscurePassword
              ? 'Mostrar contraseña'
              : 'Ocultar contraseña',
        ),
      ),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'La contraseña es obligatoria';
        }
        return null;
      },
    );
  }

  /// Botón principal con degradado y microanimación de escala.
  Widget _buildLoginButton() {
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
            onTap: _isLoading ? null : _handleLogin,
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
                        'Iniciar sesión',
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

  /// Botón secundario para crear una cuenta nueva.
  Widget _buildRegisterButton() {
    return OutlinedButton.icon(
      onPressed: _isLoading ? null : _openRegister,
      icon: const Icon(Icons.person_add_alt_1_outlined, size: 20),
      label: const Text('Crear cuenta nueva'),
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFF1976D2),
        side: const BorderSide(color: Color(0xFF1976D2), width: 1.4),
        backgroundColor: Colors.white.withValues(alpha: 0.55),
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        textStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Capa de fondo decorativa (degradado + formas en movimiento).
          Positioned.fill(
            child: _BackgroundLayer(
              entranceAnimation: _backgroundEntrance,
              backgroundController: _backgroundController,
            ),
          ),

          // Contenido de la pantalla.
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 24,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Bloque 1: Logo + identidad visual.
                        _buildLogoBlock(),

                        const SizedBox(height: 28),

                        // Bloque 2: Tarjeta con el formulario completo.
                        _buildGlassCard(),
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

/// Capa de fondo: degradado + formas abstractas decorativas.
class _BackgroundLayer extends StatelessWidget {
  final Animation<double> entranceAnimation;
  final AnimationController backgroundController;

  const _BackgroundLayer({
    required this.entranceAnimation,
    required this.backgroundController,
  });

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: entranceAnimation,
      child: AnimatedBuilder(
        animation: backgroundController,
        builder: (context, _) {
          final drift = backgroundController.value;

          return Stack(
            children: [
              // Degradado de fondo: blanco -> azul muy claro -> celeste.
              Positioned.fill(
                child: Container(
                  decoration: const BoxDecoration(
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
                top: -60,
                right: -70,
                child: _Orb(
                  size: 260,
                  color: Colors.blue.withValues(alpha: 0.14),
                ),
              ),

              // Anillo tipo "lente" (guiño a la visión): arriba izquierda.
              Positioned(
                top: 70,
                left: -70,
                child: _VisionRing(
                  size: 200,
                  borderWidth: 22,
                  color: Colors.blue.withValues(alpha: 0.08),
                ),
              ),

              // Forma celeste con movimiento lento: abajo izquierda.
              Positioned(
                bottom: 90,
                left: -80,
                child: Transform.translate(
                  offset: Offset(14 * drift, -10 * drift),
                  child: _Orb(
                    size: 240,
                    color: const Color(0xFF7FD8F7).withValues(alpha: 0.12),
                  ),
                ),
              ),

              // Detalle verde muy sutil: abajo derecha.
              Positioned(
                bottom: 40,
                right: -30,
                child: Transform.translate(
                  offset: Offset(-8 * drift, 6 * drift),
                  child: _Orb(
                    size: 140,
                    color: const Color(0xFFB9F0D4).withValues(alpha: 0.10),
                  ),
                ),
              ),

              // Segundo anillo tipo lente: abajo derecha.
              Positioned(
                bottom: 130,
                right: -50,
                child: _VisionRing(
                  size: 130,
                  borderWidth: 16,
                  color: const Color(0xFF4FC3F7).withValues(alpha: 0.07),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Forma circular con gradiente radial (luz suave).
class _Orb extends StatelessWidget {
  final double size;
  final Color color;

  const _Orb({required this.size, required this.color});

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

/// Anillo circular decorativo, inspirado en una lente o un ojo.
class _VisionRing extends StatelessWidget {
  final double size;
  final double borderWidth;
  final Color color;

  const _VisionRing({
    required this.size,
    required this.borderWidth,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color, width: borderWidth),
      ),
    );
  }
}