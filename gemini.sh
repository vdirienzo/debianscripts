#!/bin/bash
# ============================================================================
# Script de Mantenimiento Integral para Debian 13 (Testing/Trixie)
# ============================================================================
# Versión: 2025.12
# Última revisión: Diciembre 2025 - Corrección de Bugs y Numeración
# Autor: Homero Thompson del Lago del Terror
#
# Filosofía de Ejecución: Máxima seguridad para la rama Testing.
#   1.  Verificar dependencias y espacio libre.
#   2.  Asegurar un punto de retorno (Backup Tar + Timeshift Snapshot).
#   3.  Analizar riesgos de APT (detener si se proponen borrados masivos).
#   4.  Actualizar solo si es seguro.
#   5.  Limpieza profunda post-actualización.
#
# ====================== REQUISITOS DEL SISTEMA ======================
# Este script requiere permisos de root (sudo) para su ejecución.
# Herramientas Opcionales (Altamente recomendadas para modo "Paranoico"):
#   • timeshift:      Para crear snapshots Btrfs o Rsync antes de actualizar.
#   • byobu:          Contiene la herramienta 'purge-old-kernels'.
#   • needrestart:    Para verificar qué servicios necesitan reinicio post-update.
#   • flatpak:        Si utilizas paquetes Flatpak.
#   • snapd:          Si utilizas paquetes Snap.
#   • fwupd:          Para verificar y gestionar actualizaciones de firmware.
#
# Comandos de instalación:
#   sudo apt install timeshift byobu needrestart flatpak fwupd
#
# ====================== CONFIGURACIÓN ORIGINAL ======================
# BACKUP_DIR: Directorio donde se guardan los backups de configuración.
# LOCK_FILE: Archivo de bloqueo para evitar ejecuciones simultáneas.
# LOG_DIR: Directorio para archivos de registro de ejecución.
# DIAS_LOGS: Límite de días para mantener el journal de systemd.
# KERNELS_TO_KEEP: Número de kernels que se deben mantener instalados.
# MIN_FREE_SPACE_GB: Espacio mínimo requerido en la partición raíz (/).
# MIN_FREE_SPACE_BOOT_MB: Espacio mínimo requerido en la partición /boot.
# ENABLE_FIRMWARE_CHECK: Si es 'true', verifica actualizaciones con fwupdmgr.
# ENABLE_BACKUP: Si es 'true', realiza el backup de archivos de configuración (`/etc`).
# APT_CLEAN_MODE: Método de limpieza de caché de paquetes ('autoclean' o 'clean').
#
# ====================== SEGURIDAD PARANOICA ======================
# MAX_REMOVALS_ALLOWED: Número máximo de paquetes que APT puede eliminar
#                       automáticamente. Si se supera, el script ABORTA
#                       o pide confirmación. (0 es el valor más seguro para Testing).
# ENABLE_TIMESHIFT: Activa la creación de un Snapshot con Timeshift.
# ASK_TIMESHIFT_RUN: Si es 'true', preguntará al usuario si desea crear el
#                    snapshot de Timeshift en esta ejecución (solo si no es -y).
# LC_ALL=C: Fuerza el entorno estándar (C) para asegurar el correcto
#           análisis de salida de comandos como `apt`, `df`, `grep` y `awk`.
# dpkg --configure -a: Ejecutado al inicio para reparar la base de datos de paquetes
#                      antes de cualquier operación de red.
#
# ====================== EJEMPLOS DE USO ======================
# 1. Ejecución interactiva normal (Recomendada):
#    sudo ./gemini.sh
#
# 2. Modo Dry Run (Simulación, la más segura para probar):
#    sudo ./gemini.sh --dry-run
#
# 3. Ejecución desatendida (Usar con extrema precaución en Testing):
#    sudo ./gemini.sh -y
#
# 4. Ejecución sin backup de configuración (pero con Timeshift):
#    sudo ./gemini.sh --no-backup
# ============================================================================

# Forzar idioma estándar para que grep/awk funcionen predeciblemente
export LC_ALL=C

# ====================== CONFIGURACIÓN Y ESTADOS ======================
BACKUP_DIR="/var/backups/debian-maintenance"
LOCK_FILE="/var/run/debian-maintenance.lock"
LOG_DIR="/var/log/debian-maintenance"
SCRIPT_VERSION="2025.12-paranoid-hybrid-v3.2"

DIAS_LOGS=7
KERNELS_TO_KEEP=3
MIN_FREE_SPACE_GB=5
MIN_FREE_SPACE_BOOT_MB=200
ENABLE_FIRMWARE_CHECK=true
ENABLE_BACKUP=true
ENABLE_HELD_CHECK=true
APT_CLEAN_MODE="autoclean"

# Configuración de Seguridad Extra
MAX_REMOVALS_ALLOWED=0
ENABLE_TIMESHIFT=true
ASK_TIMESHIFT_RUN=true 

# Estados Visuales
STAT_REPO="⏳"
STAT_TIMESHIFT="⏩ (desactivado)"
STAT_UPGRADE="⏳"
STAT_FLATPAK="⏳"
STAT_SNAP="⏳"
STAT_FIRMWARE="⏳"
STAT_CLEAN_APT="⏳"
STAT_CLEAN_KERNEL="⏳"
STAT_CLEAN_DISK="⏳"
STAT_REBOOT="✅ No requerido"

SPACE_BEFORE_ROOT=0
SPACE_BEFORE_BOOT=0
START_TIME=$(date +%s)

# Variables de Control
DRY_RUN=false
UNATTENDED=false
QUIET=false
REBOOT_NEEDED=false

# ====================== COLORES ======================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'
ICON_OK="✅"
ICON_FAIL="❌"
ICON_SKIP="⏩"
ICON_WARN="⚠️"
ICON_SHIELD="🛡️"

# ====================== FUNCIONES BASE Y UTILITY ======================
init_log() {
    mkdir -p "$LOG_DIR"
    LOG_FILE="$LOG_DIR/sys-update-$(date +%Y%m%d_%H%M%S).log"
    touch "$LOG_FILE"
    chmod 600 "$LOG_FILE"
}

log() {
    local level="$1"; shift; local message="$*"; local ts=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${ts}] [${level}] ${message}" >> "$LOG_FILE"
    [ "$QUIET" = true ] && return
    case "$level" in
        ERROR)   echo -e "${RED}❌ ${message}${NC}" ;;
        WARN)    echo -e "${YELLOW}⚠️  ${message}${NC}" ;;
        SUCCESS) echo -e "${GREEN}✅ ${message}${NC}" ;;
        INFO)    echo -e "${CYAN}ℹ️  ${message}${NC}" ;;
        *)       echo "$message" ;;
    esac
}

die() {
    log "ERROR" "CRÍTICO: $1"
    echo -e "\n${RED}${BOLD}⛔ PROCESO ABORTADO: $1${NC}"
    rm -f "$LOCK_FILE" 2>/dev/null
    exit 1
}

safe_run() {
    local cmd="$1"; local err_msg="$2"
    log "INFO" "Ejecutando: $cmd"
    if [ "$DRY_RUN" = true ]; then 
        log "INFO" "[DRY-RUN] $cmd"
        echo -e "${YELLOW}[DRY-RUN]${NC} $cmd"
        return 0
    fi
    if eval "$cmd" >> "$LOG_FILE" 2>&1; then return 0; else log "ERROR" "$err_msg"; return 1; fi
}

print_step() {
    [ "$QUIET" = true ] && return
    echo -e "\n${BLUE}${BOLD}>>> $1${NC}"
    log "INFO" "PASO: $1"
}

print_header() {
    [ "$QUIET" = true ] && return
    clear
    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║   MANTENIMIENTO DEBIAN 13 (TESTING) - v${SCRIPT_VERSION}      ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    [ "$DRY_RUN" = true ] && echo -e "${YELLOW}🔍 MODO DRY-RUN ACTIVADO${NC}\n"
}

cleanup() { rm -f "$LOCK_FILE" 2>/dev/null; log "INFO" "Lock eliminado"; }
trap cleanup EXIT INT TERM

# ====================== CHEQUEOS PREVIOS ======================
check_root() { [ "$EUID" -eq 0 ] || { echo -e "${RED}❌ Requiere sudo${NC}"; exit 1; } }

check_lock() {
    if [ -f "$LOCK_FILE" ]; then
        pid=$(cat "$LOCK_FILE")
        if kill -0 "$pid" 2>/dev/null; then echo -e "${RED}❌ Ya está corriendo${NC}"; exit 1; fi
        rm -f "$LOCK_FILE"
    fi
    echo $$ > "$LOCK_FILE"
    # Verificación extra de APT lock
    if fuser /var/lib/dpkg/lock* /var/lib/apt/lists/lock* 2>/dev/null | grep -q .; then
        echo -e "${RED}❌ APT ocupado${NC}"; exit 1
    fi
}

check_connectivity() {
    print_step "Verificando conectividad..."
    if ! ping -c 1 deb.debian.org >/dev/null 2>&1; then
        die "Sin conexión a internet. Abortando."
    else
        log "SUCCESS" "Conexión online."
    fi
}

check_dependencies() {
    print_step "Verificando herramientas recomendadas..."
    missing=""
    command -v purge-old-kernels >/dev/null || missing="${missing}  • byobu (limpieza kernels)\n"
    command -v needrestart >/dev/null || missing="${missing}  • needrestart (reinicio servicios)\n"
    command -v fwupdmgr >/dev/null || missing="${missing}  • fwupd (firmware)\n"
    command -v timeshift >/dev/null || missing="${missing}  • timeshift (snapshots de seguridad)\n"

    if [ -n "$missing" ]; then
        echo -e "${YELLOW}⚠️ Faltan herramientas recomendadas:${NC}"
        printf "$missing"
        echo -e "\nInstalar con: sudo apt install byobu needrestart fwupd timeshift"
        [ "$UNATTENDED" = false ] && read -p "¿Continuar sin ellas? (s/N): " -n 1 -r && echo && [[ ! $REPLY =~ ^[Ss]$ ]] && exit 1
    else
        [ "$QUIET" = false ] && echo -e "${GREEN}✅ Todas las herramientas recomendadas están instaladas${NC}"
        log "SUCCESS" "Herramientas recomendadas OK"
    fi
}

check_disk_space() {
    print_step "Verificando espacio..."
    root_gb=$(df / --output=avail | tail -1 | awk '{print int($1/1024/1024)}')
    boot_mb=$(df /boot --output=avail 2>/dev/null | tail -1 | awk '{print int($1/1024)}' || echo 0)
    
    [ "$QUIET" = false ] && echo "→ /: ${root_gb} GB libre | /boot: ${boot_mb} MB libre"
    
    (( root_gb < MIN_FREE_SPACE_GB )) && die "Espacio insuficiente en / (${root_gb}GB < ${MIN_FREE_SPACE_GB}GB)"
    
    SPACE_BEFORE_ROOT=$(df / --output=used | tail -1 | awk '{print $1}')
    SPACE_BEFORE_BOOT=$(df /boot --output=used 2>/dev/null | tail -1 | awk '{print $1}' || echo 0)
}

# ====================== FUNCIONES DE BACKUP Y SEGURIDAD ======================
create_backup() {
    # Función Original de Backup de Archivos (tar)
    [ "$ENABLE_BACKUP" = false ] && return
    print_step "Creando backup de configuraciones (Tar)..."
    mkdir -p "$BACKUP_DIR"
    d=$(date +%Y%m%d_%H%M%S)
    tar czf "$BACKUP_DIR/backup_${d}.tar.gz" /etc/apt/sources.list* /etc/apt/sources.list.d/ /etc/apt/trusted.gpg.d/ 2>/dev/null
    dpkg --get-selections > "$BACKUP_DIR/packages_${d}.list"
    ls -t "$BACKUP_DIR"/backup_*.tar.gz 2>/dev/null | tail -n +6 | xargs -r rm -f
    log "SUCCESS" "Backup Tar creado"
}

create_snapshot() {
    # Función Timeshift (NUEVA LÓGICA DE CONTROL MANUAL)
    if [ "$ENABLE_TIMESHIFT" = true ] && command -v timeshift >/dev/null; then
        print_step "${ICON_SHIELD} Creando Snapshot de Sistema (Timeshift)..."

        # Lógica de Pregunta para Omitir Timeshift
        if [ "$ASK_TIMESHIFT_RUN" = true ] && [ "$UNATTENDED" = false ] && [ "$DRY_RUN" = false ]; then
            echo -e "${YELLOW}¿Deseas OMITIR la creación del Snapshot de Timeshift ahora?${NC}"
            read -p "Escribe 's' para OMITIR, cualquier otra tecla para CREAR: " -n 1 -r REPLY_TS
            echo
            if [[ $REPLY_TS =~ ^[Ss]$ ]]; then
                log "WARN" "Usuario decidió omitir el snapshot de Timeshift."
                STAT_TIMESHIFT="${YELLOW}${ICON_SKIP} Omitido por usuario${NC}"
                return
            fi
        elif [ "$UNATTENDED" = true ]; then
            log "INFO" "Modo desatendido, forzando creación de snapshot Timeshift."
        fi
        
        if [ "$DRY_RUN" = true ]; then
            STAT_TIMESHIFT="${YELLOW}Simulado${NC}"
            return
        fi

        TS_COMMENT="Pre-Maintenance $(date +%Y-%m-%d)"
        # Intentamos crear el snapshot. Si falla, ABORTAMOS.
        if timeshift --create --comments "$TS_COMMENT" --tags O >> "$LOG_FILE" 2>&1; then
            log "SUCCESS" "Snapshot Timeshift creado"
            STAT_TIMESHIFT="${GREEN}${ICON_OK} Creado${NC}"
        else
            STAT_TIMESHIFT="${RED}FALLÓ${NC}"
            die "No se pudo crear el snapshot de Timeshift. Abortando por seguridad."
        fi
    else
        STAT_TIMESHIFT="${YELLOW}No disponible/Desactivado${NC}"
    fi
}

analyze_and_upgrade() {
    # Reparar dpkg antes de nada
    dpkg --configure -a >> "$LOG_FILE" 2>&1

    # PASO 1/9
    print_step "[1/9] Actualizando repositorios..."
    safe_run "apt update" && STAT_REPO="$ICON_OK" || die "Error al actualizar repositorios"

    # PASO 2/9
    print_step "[2/9] Analizando y aplicando actualizaciones..."
    
    UPDATES_OUTPUT=$(apt list --upgradable 2>/dev/null)
    # 1. Contar los paquetes, asegurando que sea un número (o 0).
    UPDATES=$(echo "$UPDATES_OUTPUT" | grep -c '\[upgradable' || echo 0)
    # 2. Forzar que la variable solo contenga dígitos y usar 0 si está vacía (FIX)
    UPDATES=${UPDATES//[^0-9]/}
    UPDATES=${UPDATES:-0}
    UPDATES=$((UPDATES + 0))
    # FIN DEL FIX: UPDATES es ahora un entero limpio.

    if (( UPDATES > 0 )); then
        [ "$QUIET" = false ] && echo "→ $UPDATES paquetes para actualizar"
        
        # Análisis Heurístico de Riesgo (Borrados masivos)
        log "INFO" "Simulando actualización para detectar borrados..."
        SIMULATION=$(apt full-upgrade -s)
        REMOVE_COUNT=$(echo "$SIMULATION" | grep "^Remv" | wc -l)
        
        if [ "$REMOVE_COUNT" -gt "$MAX_REMOVALS_ALLOWED" ]; then
            echo -e "\n${RED}${BOLD}⚠️  ALERTA DE SEGURIDAD: APT propone eliminar $REMOVE_COUNT paquetes${NC}"
            echo "$SIMULATION" | grep "^Remv" | head -n 5 | sed 's/^Remv/ - Eliminando:/'
            
            if [ "$UNATTENDED" = true ]; then
                die "Abortado automáticamente por riesgo de eliminación de paquetes en modo desatendido."
            fi
            
            echo -e "\n${YELLOW}¿Tienes un snapshot válido? ¿Quieres proceder?${NC}"
            read -p "Escribe 'SI' para continuar: " -r CONFIRM
            if [ "$CONFIRM" != "SI" ]; then die "Cancelado por el usuario."; fi
        fi

        # Ejecución del Upgrade
        safe_run "apt full-upgrade -y" && STAT_UPGRADE="$ICON_OK ($UPDATES instalados)" || STAT_UPGRADE="$ICON_FAIL"
    else
        [ "$QUIET" = false ] && echo "→ Sistema ya actualizado"
        STAT_UPGRADE="$ICON_OK (sin cambios)"
    fi
}

# ====================== FUNCIONES DE ACTUALIZACIÓN Y LIMPIEZA ======================
other_updates() {
    # PASO 3/9
    if command -v flatpak >/dev/null; then
        print_step "[3/9] Actualizando Flatpak..."
        safe_run "flatpak update -y && flatpak uninstall --unused -y && flatpak repair" && STAT_FLATPAK="$ICON_OK" || STAT_FLATPAK="$ICON_FAIL"
    else
        STAT_FLATPAK="$ICON_SKIP (no instalado)"
    fi

    # PASO 4/9
    if command -v snap >/dev/null; then
        print_step "[4/9] Actualizando Snap..."
        safe_run "snap refresh" && STAT_SNAP="$ICON_OK" || STAT_SNAP="$ICON_FAIL"
    else
        STAT_SNAP="$ICON_SKIP (no instalado)"
    fi
}

check_firmware() {
    # PASO 5/9
    if [ "$ENABLE_FIRMWARE_CHECK" = true ] && command -v fwupdmgr >/dev/null; then
        print_step "[5/9] Verificando firmware..."
        safe_run "fwupdmgr refresh --force" || true
        if fwupdmgr get-updates 2>/dev/null | grep -q "│.*│.*│.*│.*│.*│.*│ [A-Z]"; then
            STAT_FIRMWARE="${YELLOW}${ICON_WARN} Disponible${NC}"
            [ "$QUIET" = false ] && echo -e "${YELLOW}→ Actualizaciones de firmware disponibles (ejecutar: sudo fwupdmgr update)${NC}"
        else
            STAT_FIRMWARE="$ICON_OK"
        fi
    else
        STAT_FIRMWARE="$ICON_SKIP"
    fi
}

cleanup_system() {
    # PASO 6/9
    print_step "[6/9] Limpieza APT..."
    safe_run "apt autoremove -y && apt purge -y ~c && apt $APT_CLEAN_MODE" && STAT_CLEAN_APT="$ICON_OK" || STAT_CLEAN_APT="$ICON_FAIL"

    # PASO 7/9
    print_step "[7/9] Limpiando kernels antiguos..."
    if command -v purge-old-kernels >/dev/null; then
        if [ "$DRY_RUN" = false ]; then
            purge-old-kernels --keep "$KERNELS_TO_KEEP" -q >> "$LOG_FILE" 2>&1 && safe_run "update-grub"
            STAT_CLEAN_KERNEL="$ICON_OK (o nada que limpiar)"
        else
            STAT_CLEAN_KERNEL="$ICON_OK (simulado)"
        fi
    else
        STAT_CLEAN_KERNEL="$ICON_SKIP (instalar byobu)"
    fi

    # PASO 8/9
    print_step "[8/9] Limpieza logs y caché..."
    journalctl --vacuum-time=${DIAS_LOGS}d --vacuum-size=500M >/dev/null 2>&1
    find /var/tmp -type f -atime +30 -delete 2>/dev/null
    for h in /home/*; do [ -d "$h/.cache/thumbnails" ] && rm -rf "$h/.cache/thumbnails/"* 2>/dev/null; done
    STAT_CLEAN_DISK="$ICON_OK"
}

check_reboot() {
    # PASO 9/9
    print_step "[9/9] Verificando reinicio..."
    if [ -f /var/run/reboot-required ]; then
        REBOOT_NEEDED=true
        [ "$QUIET" = false ] && echo -e "${YELLOW}→ Reinicio necesario por actualización crítica${NC}"
    fi
    if command -v needrestart >/dev/null; then
        [ "$DRY_RUN" = false ] && safe_run "needrestart -r a" "Error needrestart"
    fi
    [ "$REBOOT_NEEDED" = true ] && STAT_REBOOT="${RED}${ICON_WARN} REQUERIDO${NC}" || STAT_REBOOT="${GREEN}${ICON_OK} No necesario${NC}"
}

# ====================== ARGUMENTOS ======================
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run) DRY_RUN=true ;;
        -y|--unattended) UNATTENDED=true ;;
        --no-backup) ENABLE_BACKUP=false ;;
        --quiet) QUIET=true ;;
        --help) cat << 'EOF'
Uso: sudo $0 [opciones]
  --dry-run      Simular
  -y             Sin preguntas (ABORTA si hay riesgo de borrado)
  --no-backup    Sin backup de archivos (Timeshift sigue activo si está instalado)
  --quiet        Silencioso
EOF
            exit 0 ;;
        *) echo "Opción desconocida: $1"; exit 1 ;;
    esac
    shift
done

# ====================== EJECUCIÓN MAESTRA ======================
init_log
log "INFO" "Iniciando Mantenimiento Paranoico v${SCRIPT_VERSION}"
[ "$QUIET" = false ] && print_header

# --- Chequeos Previos ---
check_root
check_lock
check_connectivity
check_dependencies
check_disk_space

# --- Backups y Seguridad ---
create_backup
create_snapshot 

# --- Actualizaciones ---
analyze_and_upgrade
other_updates
check_firmware

# --- Limpieza ---
cleanup_system

# --- Post-vuelo ---
check_reboot

# 6. Finalización
rm -f "$LOCK_FILE"

# ====================== RESUMEN FINAL ======================
END_TIME=$(date +%s)
MINUTES=$(((END_TIME - START_TIME)/60))
SECONDS=$(((END_TIME - START_TIME)%60))

# Los siguientes comandos se ejecutan sin `safe_run` para obtener el espacio post-limpieza.
SPACE_ROOT=$(((SPACE_BEFORE_ROOT - $(df / --output=used | tail -1 | awk '{print $1}')) / 1024))
SPACE_BOOT=$(((SPACE_BEFORE_BOOT - $(df /boot --output=used 2>/dev/null | tail -1 | awk '{print $1}' || echo 0)) / 1024))

[ "$QUIET" = true ] && exit 0

echo -e "\n${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║            RESUMEN DEL MANTENIMIENTO (PARANOID)               ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo
echo -e "  ${ICON_SHIELD} Timeshift:           $STAT_TIMESHIFT"
echo -e "  📦 Repositorios:       $STAT_REPO"
echo -e "  ⬆️  Actualización APT: $STAT_UPGRADE"
echo -e "  📦 Flatpak:            $STAT_FLATPAK"
echo -e "  🔄 Snap:               $STAT_SNAP"
echo -e "  🔌 Firmware:           $STAT_FIRMWARE"
echo -e "  🧹 Limpieza APT:       $STAT_CLEAN_APT"
echo -e "  🧠 Kernels antiguos:   $STAT_CLEAN_KERNEL"
echo -e "  💾 Logs y caché:       $STAT_CLEAN_DISK"
echo -e "  🔄 Reinicio:           $STAT_REBOOT"
echo
echo -e "  💿 Espacio liberado en /:     ${SPACE_ROOT:-0} MB"
echo -e "  💿 Espacio liberado en /boot: ${SPACE_BOOT:-0} MB"
echo -e "  ⏱️  Tiempo total:             ${MINUTES}m ${SECONDS}s"
echo

if [ "$REBOOT_NEEDED" = true ] && [ "$UNATTENDED" = false ]; then
    read -p "¿Reiniciar ahora? (s/N): " -n 1 -r
    echo
    [[ $REPLY =~ ^[Ss]$ ]] && reboot
fi

echo "📄 Log: $LOG_FILE"
[ "$ENABLE_BACKUP" = true ] && echo "💾 Backups Tar: $BACKUP_DIR"
echo

exit 0
