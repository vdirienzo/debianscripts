
## Script Viejo
#sudo apt update && sudo apt -y full-upgrade && sudo apt -y autoremove && sudo apt -y purge $(dpkg -l | awk '/^rc/ {print $2}') && sudo apt clean && sudo journalctl --vacuum-time=7d

##Nuevo Script Actualizado
#!/bin/bash
# Script de actualización completa para Debian 13/Testing
# Versión profesional con manejo robusto de errores
# Autor: Sistema de actualización automatizado
# Última actualización: 2025

# ============================================================================
# CONFIGURACIÓN INICIAL Y VALIDACIONES
# ============================================================================

# Modo estricto: detener ante errores, pero permitir pipefails controlados
set -e

# Verificar que se ejecuta en Debian/Ubuntu
if ! command -v apt &>/dev/null; then
    echo "ERROR: Este script solo funciona en sistemas basados en Debian/Ubuntu"
    exit 1
fi

# Verificar permisos de sudo antes de comenzar
if ! sudo -v; then
    echo "ERROR: Se requieren permisos de sudo para ejecutar este script"
    exit 1
fi

# Mantener sudo activo durante la ejecución
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

# Colores para output (verificar soporte de terminal)
if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    BOLD='\033[1m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    BOLD=''
    NC=''
fi

# ============================================================================
# FUNCIONES AUXILIARES
# ============================================================================

print_header() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║     SCRIPT DE ACTUALIZACIÓN COMPLETA DEL SISTEMA DEBIAN        ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
}

print_section() {
    echo ""
    echo -e "${BLUE}${BOLD}$1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

# Función para log de errores
log_error() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] ERROR: $1" >> /tmp/debian-update-errors.log
}

# ============================================================================
# INICIO DEL SCRIPT
# ============================================================================

print_header

# ============================================================================
# [1/8] ACTUALIZAR REPOSITORIOS
# ============================================================================
print_section "[1/8] 📦 ACTUALIZANDO LISTA DE REPOSITORIOS"
echo "→ Esto descarga la lista actualizada de paquetes disponibles"
echo "→ No instala nada todavía, solo actualiza el índice"

if ! sudo apt update; then
    print_error "Error al actualizar repositorios"
    log_error "apt update falló"
    exit 1
fi

# ============================================================================
# [2/8] REVISAR PAQUETES DISPONIBLES
# ============================================================================
print_section "[2/8] 🔍 REVISANDO PAQUETES DISPONIBLES PARA ACTUALIZAR"
echo "→ Estos son los paquetes que tienen nuevas versiones:"

# Usar variable temporal para evitar subshell issues
upgradable_file=$(mktemp)
apt list --upgradable 2>/dev/null | tail -n +2 > "$upgradable_file" || true

if [ ! -s "$upgradable_file" ]; then
    print_success "El sistema está completamente actualizado"
else
    head -20 "$upgradable_file"
    count=$(wc -l < "$upgradable_file")
    if [ "$count" -gt 20 ]; then
        echo "... y $((count - 20)) paquetes más"
    fi
fi
rm -f "$upgradable_file"

read -p "¿Continuar con la actualización? (S/n): " -r respuesta
if [[ $respuesta =~ ^[Nn]$ ]]; then
    echo "Actualización cancelada por el usuario"
    exit 0
fi

# ============================================================================
# [3/8] FULL-UPGRADE
# ============================================================================
print_section "[3/8] ⬆️  ACTUALIZANDO SISTEMA COMPLETO (full-upgrade)"
echo "→ Esto actualiza TODOS los paquetes instalados a sus últimas versiones"
echo "→ Incluye: aplicaciones, bibliotecas, kernel y paquetes del sistema"
echo "→ Puede instalar o remover paquetes si es necesario para resolver dependencias"
echo "→ Iniciando actualización..."

# Configurar apt para evitar prompts interactivos
export DEBIAN_FRONTEND=noninteractive

if ! sudo -E apt full-upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"; then
    print_error "Error durante full-upgrade"
    log_error "apt full-upgrade falló"
    exit 1
fi

# ============================================================================
# [4/8] AUTOREMOVE
# ============================================================================
print_section "[4/8] 🧹 REMOVIENDO PAQUETES HUÉRFANOS (autoremove)"
echo "→ Los paquetes huérfanos son dependencias que ya no necesita ningún programa"
echo "→ Se instalaron automáticamente pero ahora están obsoletos"
echo "→ Es seguro eliminarlos para liberar espacio en disco"

if ! sudo apt autoremove -y; then
    print_warning "Hubo un problema al remover paquetes huérfanos (continuando...)"
    log_error "apt autoremove falló"
fi

# ============================================================================
# [5/8] PURGAR PAQUETES RESIDUALES
# ============================================================================
print_section "[5/8] 🗑️  PURGANDO PAQUETES RESIDUALES"
echo "→ Los paquetes residuales (estado 'rc') fueron desinstalados pero dejaron"
echo "→ archivos de configuración en el sistema"
echo "→ Purgar significa eliminar completamente estos archivos"

# Capturar paquetes residuales de forma segura
residuales=$(dpkg -l 2>/dev/null | awk '/^rc/ {print $2}' || true)

if [ -n "$residuales" ]; then
    echo "→ Paquetes residuales encontrados:"
    echo "$residuales" | sed 's/^/   - /'
    
    read -p "¿Purgar estos paquetes? (s/N): " -r respuesta
    if [[ $respuesta =~ ^[SsYy]$ ]]; then
        # Purgar uno por uno para evitar fallos en batch
        while IFS= read -r pkg; do
            if ! sudo apt purge -y "$pkg" 2>/dev/null; then
                print_warning "No se pudo purgar: $pkg"
            fi
        done <<< "$residuales"
        print_success "Paquetes residuales purgados"
    else
        echo "Purgado cancelado"
    fi
else
    print_success "No hay paquetes residuales en el sistema"
fi

# ============================================================================
# [6/8] AUTOCLEAN
# ============================================================================
print_section "[6/8] 💾 LIMPIANDO CACHE DE PAQUETES (autoclean)"
echo "→ APT guarda los archivos .deb descargados en /var/cache/apt/archives/"
echo "→ autoclean elimina solo los paquetes obsoletos (versiones antiguas)"
echo "→ Los paquetes actuales se conservan por si necesitas reinstalar"

if [ -d /var/cache/apt/archives ]; then
    cache_before=$(du -sh /var/cache/apt/archives 2>/dev/null | awk '{print $1}' || echo "desconocido")
    echo "→ Tamaño actual del cache: $cache_before"
    
    if sudo apt autoclean; then
        cache_after=$(du -sh /var/cache/apt/archives 2>/dev/null | awk '{print $1}' || echo "desconocido")
        echo "→ Tamaño después de limpiar: $cache_after"
    else
        print_warning "Error al ejecutar autoclean (continuando...)"
    fi
else
    print_warning "Directorio de cache no encontrado"
fi

# ============================================================================
# [7/8] LIMPIAR LOGS
# ============================================================================
print_section "[7/8] 📋 LIMPIANDO LOGS DEL SISTEMA (journalctl)"
echo "→ systemd-journald guarda logs en /var/log/journal/"
echo "→ Estos logs pueden crecer mucho con el tiempo"
echo "→ Vamos a eliminar logs más antiguos de 7 días"
echo "→ Y limitar el tamaño total a 100MB"

if command -v journalctl &>/dev/null; then
    if [ -d /var/log/journal ]; then
        journal_before=$(du -sh /var/log/journal 2>/dev/null | awk '{print $1}' || echo "desconocido")
        echo "→ Espacio usado por logs: $journal_before"
        
        if sudo journalctl --vacuum-time=7d --vacuum-size=100M 2>/dev/null; then
            journal_after=$(du -sh /var/log/journal 2>/dev/null | awk '{print $1}' || echo "desconocido")
            echo "→ Espacio usado después: $journal_after"
        else
            print_warning "Error al limpiar logs del journal (continuando...)"
        fi
    else
        echo "→ No hay logs persistentes del journal"
    fi
else
    print_warning "journalctl no está disponible"
fi

# ============================================================================
# [8/8] VERIFICAR NECESIDAD DE REINICIO
# ============================================================================
print_section "[8/8] 🔄 VERIFICANDO NECESIDAD DE REINICIO"
echo "→ Algunos paquetes (como el kernel o bibliotecas críticas) requieren"
echo "→ reiniciar el sistema para que los cambios surtan efecto"

# Verificar archivo estándar de reinicio
reboot_needed=false
if [ -f /var/run/reboot-required ]; then
    print_warning "REINICIO REQUERIDO"
    reboot_needed=true
    
    if [ -f /var/run/reboot-required.pkgs ]; then
        echo "→ Paquetes que lo requieren:"
        cat /var/run/reboot-required.pkgs | sed 's/^/   - /'
    fi
else
    print_success "No es necesario reiniciar el sistema en este momento"
fi

# ============================================================================
# INFORMACIÓN DEL KERNEL
# ============================================================================
echo ""
echo "📊 INFORMACIÓN DEL KERNEL"

# Kernel en ejecución
kernel_running=$(uname -r)
echo "→ Kernel en ejecución:  $kernel_running"

# Kernel más reciente instalado
if [ -d /boot ]; then
    # Buscar el kernel más reciente instalado
    kernel_latest=$(ls -1 /boot/vmlinuz-* 2>/dev/null | sort -V | tail -1 | sed 's|.*/vmlinuz-||' || echo "")
    
    if [ -n "$kernel_latest" ]; then
        echo "→ Kernel más reciente:  $kernel_latest"
        
        # Comparar versiones
        if [ "$kernel_running" = "$kernel_latest" ]; then
            print_success "Estás usando el kernel más reciente"
        else
            print_warning "Hay un kernel más nuevo instalado"
            echo "→ Se activará después de reiniciar el sistema"
            reboot_needed=true
        fi
    else
        print_warning "No se pudo detectar el kernel instalado"
    fi
else
    print_warning "Directorio /boot no encontrado"
fi

# Listar kernels antiguos
echo ""
old_kernels=$(dpkg -l 2>/dev/null | grep '^ii' | grep 'linux-image-[0-9]' | grep -v "$(uname -r)" | awk '{print $2}' | grep -v 'linux-image-amd64$' || true)

if [ -n "$old_kernels" ]; then
    echo "💡 KERNELS ANTIGUOS DETECTADOS:"
    echo "$old_kernels" | sed 's/^/   - /'
    echo ""
    echo "→ Para liberar espacio (~300-500MB por kernel), puedes eliminarlos:"
    echo "   sudo apt remove --purge linux-image-VERSION"
    echo ""
    echo "→ O eliminar TODOS los antiguos automáticamente:"
    echo "   sudo apt autoremove --purge"
fi

# ============================================================================
# VERIFICACIÓN ADICIONAL: Servicios que requieren reinicio
# ============================================================================
if command -v needrestart &>/dev/null; then
    echo ""
    echo "🔍 VERIFICANDO SERVICIOS QUE REQUIEREN REINICIO"
    
    # Ejecutar needrestart en modo batch
    services_to_restart=$(sudo needrestart -b 2>/dev/null | grep "NEEDRESTART-SVC:" | cut -d: -f2 || true)
    
    if [ -n "$services_to_restart" ]; then
        print_warning "Servicios que requieren reinicio:"
        echo "$services_to_restart" | sed 's/^/   - /'
        echo ""
        echo "→ Puedes reiniciarlos manualmente con: sudo systemctl restart SERVICIO"
    fi
fi

# ============================================================================
# RESUMEN FINAL
# ============================================================================
echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║              ✅ ACTUALIZACIÓN COMPLETADA EXITOSAMENTE          ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "📋 RESUMEN:"
echo "  [OK] Repositorios actualizados"
echo "  [OK] Sistema actualizado con los últimos paquetes"
echo "  [OK] Paquetes huérfanos eliminados"
echo "  [OK] Archivos residuales limpiados"
echo "  [OK] Cache de paquetes optimizado"
echo "  [OK] Logs antiguos eliminados"

if [ "$reboot_needed" = true ]; then
    echo ""
    print_warning "ACCIÓN REQUERIDA: Se recomienda reiniciar el sistema"
    echo "  → Ejecuta: sudo reboot"
else
    echo "  [OK] Sistema listo para usar"
fi

echo ""
echo "👋 ¡Gracias por mantener tu sistema actualizado!"

# Limpiar log de errores si está vacío
if [ -f /tmp/debian-update-errors.log ] && [ ! -s /tmp/debian-update-errors.log ]; then
    rm -f /tmp/debian-update-errors.log
elif [ -f /tmp/debian-update-errors.log ]; then
    echo ""
    print_warning "Se registraron algunos errores en: /tmp/debian-update-errors.log"
fi

echo ""

exit 0
