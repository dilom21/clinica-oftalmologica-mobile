import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../models/auth_models.dart';
import '../../services/auth_service.dart';
import '../../widgets/clinica_selector.dart';
import '../register/register_page.dart';
import '../../../../core/storage/token_storage.dart';
import '../../../home/pages/main_navigation_page.dart';

// El registro de nuevas cuentas vive en `RegisterPage` y siempre se hace dentro
// de la clínica elegida en el selector (registro multitenant del PASO 3).

/// Pantalla de inicio de sesión de la aplicación móvil multitenant.
///
/// La identidad visual es genérica hasta que el paciente elige su clínica: en
/// ese momento el encabezado muestra el nombre REAL que devolvió
/// `GET /seguridad/tenant/empresas` (nunca un nombre fijo en el código).
///
/// Solo contiene:
/// - Interfaz de usuario moderna (fondo degradado, glassmorphism)
/// - Animación de entrada escalonada
/// - Movimiento lento del fondo decorativo
/// - Estado visual (mostrar/ocultar contraseña)
/// - Selector de clínica (multitenant)
/// - Validaciones locales del formulario
/// - Estado de carga mientras se consulta FastAPI
///
/// NOTA: el login es multitenant. Primero se obtienen las clínicas con
/// `GET /seguridad/tenant/empresas` y el paciente elige una; luego se envían
/// `empresa_codigo`, `correo` y `password` a `POST /seguridad/tenant/login`.
/// AuthService solo acepta JWT con `token_type = "tenant"`, `rol_nombre =
/// "Paciente"` y `empresa_codigo` igual a la clínica elegida.
/// Con un login exitoso se guarda el JWT junto al código de la clínica
/// (TokenStorage) y se navega a MainNavigationPage.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key, this.authService});

  /// Servicio de autenticación inyectable (usado por las pruebas).
  ///
  /// Si no se provee, la pantalla crea su propio [AuthService].
  final AuthService? authService;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with TickerProviderStateMixin {
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

  // Clínicas disponibles para iniciar sesión (GET /seguridad/tenant/empresas).
  List<EmpresaTenant> _empresas = const [];

  // Indica si se están cargando las clínicas desde FastAPI.
  bool _cargandoClinicas = true;

  // Mensaje de error al cargar las clínicas (null si no hubo error).
  String? _errorClinicas;

  // Evita lanzar dos cargas de clínicas en paralelo (por ejemplo, al tocar
  // varias veces "Reintentar").
  bool _solicitudClinicasEnCurso = false;

  // Clínica elegida por el paciente; se envía como `empresa_codigo`.
  EmpresaTenant? _empresaSeleccionada;

  // Error local cuando se intenta iniciar sesión sin clínica.
  String? _errorSeleccion;

  // Servicio que se comunica con el backend FastAPI.
  late final AuthService _authService = widget.authService ?? AuthService();

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
  late final Animation<double> _logoScale = Tween<double>(
    begin: 0.92,
    end: 1.0,
  ).animate(_logoEntrance);

  // El botón reacciona al presionarlo: 1.0 -> 0.98 -> 1.0.
  late final Animation<double> _buttonScale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween<double>(
        begin: 1.0,
        end: 0.98,
      ).chain(CurveTween(curve: Curves.easeOut)),
      weight: 50,
    ),
    TweenSequenceItem(
      tween: Tween<double>(
        begin: 0.98,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.easeOut)),
      weight: 50,
    ),
  ]).animate(_buttonController);

  @override
  void initState() {
    super.initState();

    // Inicia la animación de entrada al abrir la pantalla.
    _entranceController.forward();

    // Obtiene las clínicas del backend (no se escriben a mano en la app).
    _cargarClinicas();
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

  /// Carga las clínicas disponibles desde FastAPI.
  ///
  /// Maneja los tres estados de la sección: carga, error (con reintento) y
  /// lista vacía. Si la clínica elegida ya no aparece en la nueva lista se
  /// limpia la selección para no autenticarse contra una clínica obsoleta.
  Future<void> _cargarClinicas() async {
    if (_solicitudClinicasEnCurso) {
      return;
    }

    _solicitudClinicasEnCurso = true;

    setState(() {
      _cargandoClinicas = true;
      _errorClinicas = null;
    });

    try {
      final List<EmpresaTenant> empresas = await _authService.listarEmpresas();

      if (!mounted) return;

      setState(() {
        _empresas = empresas;
        _cargandoClinicas = false;

        final EmpresaTenant? seleccionada = _empresaSeleccionada;

        if (seleccionada != null &&
            !empresas.any((empresa) => empresa.codigo == seleccionada.codigo)) {
          _empresaSeleccionada = null;
        }
      });
    } on AuthException catch (error) {
      if (!mounted) return;

      setState(() {
        _empresas = const [];
        _cargandoClinicas = false;
        _errorClinicas = error.message;
        _empresaSeleccionada = null;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _empresas = const [];
        _cargandoClinicas = false;
        _errorClinicas =
            'No se pudieron cargar las clínicas. Inténtalo de nuevo.';
        _empresaSeleccionada = null;
      });
    } finally {
      _solicitudClinicasEnCurso = false;
    }
  }

  /// Abre la hoja inferior con las clínicas devueltas por FastAPI.
  Future<void> _abrirSelectorClinica() async {
    if (_isLoading || _cargandoClinicas || _empresas.isEmpty) {
      return;
    }

    final EmpresaTenant? seleccionada =
        await showModalBottomSheet<EmpresaTenant>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.white,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          builder: (_) => ClinicaSheet(
            empresas: _empresas,
            seleccionada: _empresaSeleccionada,
          ),
        );

    if (seleccionada == null || !mounted) {
      return;
    }

    setState(() {
      _empresaSeleccionada = seleccionada;
      _errorSeleccion = null;
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

    if (_cargandoClinicas) {
      _showMessage('Espera a que se carguen las clínicas disponibles.');
      return;
    }

    // Sin una clínica válida del listado no se envía ninguna petición.
    if (_empresaSeleccionada == null) {
      setState(() {
        _errorSeleccion = 'Selecciona la clínica donde tienes tu cuenta';
      });
      _showMessage('Selecciona la clínica donde tienes tu cuenta');
      return;
    }

    setState(() {
      _errorSeleccion = null;
    });

    if (_formKey.currentState!.validate()) {
      _login();
    }
  }

  /// Llama a AuthService.loginPaciente() contra la clínica seleccionada.
  ///
  /// AuthService solo devuelve una sesión cuando el JWT cumple el contrato
  /// tenant (rol `Paciente`, `token_type` `tenant` y la clínica elegida). Con
  /// un login exitoso guarda el JWT junto al código/nombre de la clínica
  /// (TokenStorage, descartando la sesión anterior) y navega a
  /// MainNavigationPage eliminando LoginPage del historial. Si el JWT se
  /// rechaza, no se guarda ningún token y se borra la sesión previa.
  Future<void> _login() async {
    final EmpresaTenant? empresa = _empresaSeleccionada;

    if (empresa == null) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final request = LoginRequest(
      empresaCodigo: empresa.codigo,
      correo: _emailController.text.trim(),
      password: _passwordController.text,
    );

    try {
      final LoginResponse response = await _authService.loginPaciente(request);

      // Guardar el JWT de forma segura junto a la clínica autenticada. Esto
      // elimina cualquier token legacy o de otra clínica antes de navegar.
      await TokenStorage().saveTenantSession(
        token: response.accessToken,
        empresaCodigo: empresa.codigo,
        empresaNombre: empresa.nombre,
      );

      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const MainNavigationPage()),
        (route) => false,
      );
    } on AuthException catch (error) {
      // Si el JWT no cumple el contrato tenant (rol distinto de Paciente,
      // `token_type` que no es `tenant`, claims obligatorios ausentes o
      // clínica diferente) se descarta cualquier sesión anterior: nunca se
      // reutiliza un token que la app no pudo validar.
      if (error.sesionRechazada) {
        await TokenStorage().deleteSession();
      }

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

  /// Abre el registro de una cuenta nueva en la clínica seleccionada.
  ///
  /// La clínica es obligatoria: sin ella no se abre el formulario, para no
  /// crear cuentas en una base equivocada. [RegisterPage] recibe la clínica en
  /// modo de solo lectura y la envía como `empresa_codigo` en
  /// `POST /seguridad/tenant/registro-paciente`.
  ///
  /// La clínica se captura antes de navegar, así que no puede cambiar mientras
  /// el paciente completa el formulario. Cuando el registro termina con 201,
  /// [RegisterPage] devuelve el correo registrado: se precarga en el login, se
  /// conserva la misma clínica y el paciente solo escribe su contraseña (sin
  /// autologin ni transporte de contraseñas entre pantallas).
  Future<void> _openRegister() async {
    if (_isLoading) {
      return;
    }

    if (_cargandoClinicas) {
      _showMessage('Espera a que se carguen las clínicas disponibles.');
      return;
    }

    final EmpresaTenant? empresa = _empresaSeleccionada;

    if (empresa == null) {
      setState(() {
        _errorSeleccion = 'Selecciona la clínica para crear tu cuenta';
      });
      _showMessage('Selecciona la clínica para crear tu cuenta');
      return;
    }

    final String? correo = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) =>
            RegisterPage(empresa: empresa, authService: _authService),
      ),
    );

    if (!mounted || correo == null) {
      return;
    }

    setState(() {
      _errorSeleccion = null;
      _emailController.text = correo;
      _passwordController.clear();
    });
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

  /// Bloque de identidad visual (fade + escala).
  ///
  /// Muestra la clínica REAL elegida por el paciente (nombre que devolvió
  /// `GET /seguridad/tenant/empresas`). Antes de elegirla, o si el listado no
  /// se pudo cargar, se muestra una identidad genérica de la app.
  ///
  /// No se usa el logotipo de una clínica concreta: el backend todavía no
  /// entrega una fuente de imagen por clínica.
  Widget _buildIdentidadBlock() {
    final EmpresaTenant? empresa = _empresaSeleccionada;

    return FadeTransition(
      opacity: _logoEntrance,
      child: ScaleTransition(
        scale: _logoScale,
        child: Column(
          children: [
            // Icono neutro (sin marca de una clínica específica).
            Container(
              key: const Key('login-identidad-icono'),
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFD6ECFA), Color(0xFFB7E3F9)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF1976D2).withValues(alpha: 0.16),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: const Icon(
                Icons.local_hospital_outlined,
                size: 46,
                color: Color(0xFF0D47A1),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              empresa?.nombre ?? 'Clínica Oftalmológica',
              key: const Key('login-clinica-identidad'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: const Color(0xFF0D47A1),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              empresa == null
                  ? 'Selecciona tu clínica para continuar'
                  : 'Portal del paciente',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(color: const Color(0xFF547799)),
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
                border: Border.all(color: Colors.white.withValues(alpha: 0.6)),
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
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Ingresa tus credenciales para continuar',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: const Color(0xFF5C6F80)),
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
                        ClinicaSelector(
                          cargando: _cargandoClinicas,
                          error: _errorClinicas,
                          empresas: _empresas,
                          seleccionada: _empresaSeleccionada,
                          errorSeleccion: _errorSeleccion,
                          habilitado: !_isLoading,
                          onReintentar: _cargarClinicas,
                          onAbrir: _abrirSelectorClinica,
                        ),
                        const SizedBox(height: 16),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
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
                        // Bloque 1: Identidad de la clínica (dinámica).
                        _buildIdentidadBlock(),

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
