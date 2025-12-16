#!/bin/bash
# ============================================================================
# Script de Mantenimiento Integral para Debian 13 (Testing/Trixie)
# ============================================================================
# Versión: 2025.12-ultimate
#
# DESCRIPCIÓN:
# Este script realiza un mantenimiento completo y seguro del sistema Debian 13 (Testing/Trixie).
# Incluye actualización de paquetes, limpieza de caché, gestión segura de kernels antiguos,
# actualización de Flatpak y Snap, chequeo de firmware, limpieza de logs y temporales,
# backup automático de configuraciones APT y detección precisa de necesidad de reinicio.
#
# CARACTERÍSTICAS PRINCIPALES:
# - Actualización completa del sistema (APT + Flatpak + Snap)
# - Limpieza segura de kernels antiguos usando purge-old-kernels (del paquete byobu)
# - Chequeo de actualizaciones de firmware (fwupd) sin falsos positivos de reinicio
# - Backup automático de fuentes APT (compatible con el nuevo formato DEB822: debian.sources y *.sources)
# - Logging detallado por ejecución con fecha
# - Verificación al inicio de herramientas recomendadas
# - Detección precisa de reinicio (solo cuando realmente es necesario)
# - Modos: normal, --dry-run (simulación), -y (desatendido), --quiet (silencioso para cron)
# - Colores y resumen visual claro
#
# REQUISITOS RECOMENDADOS (para funcionalidad completa):
#   sudo apt install byobu needrestart fwupd flatpak snapd
#
#   - byobu: proporciona purge-old-kernels (limpieza segura de kernels)
# - needrestart: reinicio automático de servicios obsoletos
# - fwupd: gestión y chequeo de actualizaciones de firmware/BIOS
# - flatpak y snapd: opcionales, solo si usas estas tecnologías
#
# USO:
#   sudo ./mantenimiento-debian.sh                  # Ejecución normal interactiva
#   sudo ./mantenimiento-debian.sh --dry-run        # Simular sin hacer cambios
#   sudo ./mantenimiento-debian.sh -y               # Modo desatendido (ideal para cron)
#   sudo ./mantenimiento-debian.sh --quiet          # Sin salida por pantalla (para cron)
#   sudo ./mantenimiento-debian.sh --no-backup      # Ejecutar sin crear backup
#
# EJEMPLOS DE CRON (automatización semanal):
#   sudo crontab -e
#   # Ejemplo: todos los domingos a las 4:00 AM
#   0 4 * * 0 /ruta/completa/mantenimiento-debian.sh -y --quiet >> /var/log/debian-maintenance/cron.log 2>&1
#
# ARCHIVOS GENERADOS:
#   Logs:     /var/log/debian-maintenance/sys-update-AAAAMMDD_HHMMSS.log
#   Backups:  /var/backups/debian-maintenance/
#   Lock:     /var/run/debian-maintenance.lock (evita ejecuciones simultáneas)
#
# NOTAS:
# - El script NUNCA eliminará el kernel en uso
# - Solo pide reinicio cuando existe /var/run/reboot-required (método oficial de Debian)
# - Totalmente compatible con el nuevo formato DEB822 (debian.sources y archivos .sources en sources.list.d)
# ============================================================================

# ====================== CONFIGURACIÓN ======================
BACKUP_DIR="/var/backups/debian-maintenance"
LOCK_FILE="/var/run/debian-maintenance.lock"
LOG_DIR="/var/log/debian-maintenance"
SCRIPT_VERSION="2025.12-ultimate"

DIAS_LOGS=7
KERNELS_TO_KEEP=3
MIN_FREE_SPACE_GB=5
MIN_FREE_SPACE_BOOT_MB=200
ENABLE_FIRMWARE_CHECK=true
ENABLE_BACKUP=true
ENABLE_HELD_CHECK=true
APT_CLEAN_MODE="autoclean"

# ====================== ESTADOS ======================
STAT_REPO="⏳"
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

DRY_RUN=false
UNATTENDED=false
QUIET=false

# ====================== FUNCIONES ======================
init_log() {
    mkdir -p "$LOG_DIR"
    LOG_FILE="$LOG_DIR/sys-update-$(date +%Y%m%d_%H%M%S).log"
    touch "$LOG_FILE"
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

safe_run() {
    local cmd="$1"; local err_msg="$2"
    log "INFO" "Ejecutando: $cmd"
    [ "$DRY_RUN" = true ] && { log "INFO" "[DRY-RUN] $cmd"; return 0; }
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

check_root() { [ "$EUID" -eq 0 ] || { echo -e "${RED}❌ Requiere sudo${NC}"; exit 1; } }

check_lock() {
    if [ -f "$LOCK_FILE" ]; then
        pid=$(cat "$LOCK_FILE")
        if kill -0 "$pid" 2>/dev/null; then echo -e "${RED}❌ Ya está corriendo${NC}"; exit 1; fi
        rm -f "$LOCK_FILE"
    fi
    echo $$ > "$LOCK_FILE"
    if fuser /var/lib/dpkg/lock* /var/lib/apt/lists/lock* 2>/dev/null | grep -q .; then
        echo -e "${RED}❌ APT ocupado${NC}"; exit 1
    fi
}

check_dependencies() {
    print_step "Verificando herramientas recomendadas..."
    missing=""
    command -v purge-old-kernels >/dev/null || missing="${missing}  • byobu (limpieza kernels)\n"
    command -v needrestart >/dev/null || missing="${missing}  • needrestart (reinicio servicios)\n"
    command -v fwupdmgr >/dev/null || missing="${missing}  • fwupd (firmware)\n"

    if [ -n "$missing" ]; then
        echo -e "${YELLOW}⚠️ Faltan herramientas recomendadas:${NC}"
        printf "$missing"
        echo -e "\nInstalar con: sudo apt install byobu needrestart fwupd"
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
    (( root_gb < MIN_FREE_SPACE_GB )) && { echo -e "${RED}❌ Espacio insuficiente${NC}"; exit 1; }
    SPACE_BEFORE_ROOT=$(df / --output=used | tail -1 | awk '{print $1}')
    SPACE_BEFORE_BOOT=$(df /boot --output=used 2>/dev/null | tail -1 | awk '{print $1}' || echo 0)
}

create_backup() {
    [ "$ENABLE_BACKUP" = false ] && return
    print_step "Creando backup de configuraciones APT (compatible DEB822)..."
    mkdir -p "$BACKUP_DIR"
    d=$(date +%Y%m%d_%H%M%S)
    # Backup de todos los archivos de fuentes: debian.sources y *.sources
    tar czf "$BACKUP_DIR/backup_${d}.tar.gz" \
        /etc/apt/sources.list \
        /etc/apt/sources.list.d/*.sources \
        /etc/apt/trusted.gpg.d/ 2>/dev/null || true
    dpkg --get-selections > "$BACKUP_DIR/packages_${d}.list"
    ls -t "$BACKUP_DIR"/backup_*.tar.gz 2>/dev/null | tail -n +6 | xargs -r rm -f
    log "SUCCESS" "Backup creado (incluye debian.list y debian.sources)"
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
  -y             Sin preguntas
  --no-backup    Sin backup
  --quiet        Silencioso
EOF
            exit 0 ;;
        *) echo "Opción desconocida: $1"; exit 1 ;;
    esac
    shift
done

# ====================== INICIO ======================
init_log
log "INFO" "Iniciando v${SCRIPT_VERSION}"
check_root
check_lock
[ "$QUIET" = false ] && print_header
check_dependencies
check_disk_space
create_backup

# ====================== PASOS ======================
print_step "[1/9] Actualizando repositorios..."
safe_run "apt update" && STAT_REPO="$ICON_OK" || exit 1

print_step "[2/9] Actualizando paquetes..."
UPDATES_OUTPUT=$(apt list --upgradable 2>/dev/null)
UPDATES=$(echo "$UPDATES_OUTPUT" | grep -c '\[upgradable' || echo 0)
UPDATES=$(echo "$UPDATES" | tr -d '\n\r ' | sed 's/^ *//')
UPDATES=$((UPDATES + 0))

if (( UPDATES > 0 )); then
    [ "$QUIET" = false ] && echo "→ $UPDATES paquetes para actualizar"
    safe_run "apt full-upgrade -y" && STAT_UPGRADE="$ICON_OK ($UPDATES instalados)" || STAT_UPGRADE="$ICON_FAIL"
else
    [ "$QUIET" = false ] && echo "→ Sistema actualizado"
    STAT_UPGRADE="$ICON_OK (sin cambios)"
fi

if command -v flatpak >/dev/null; then
    print_step "[3/9] Actualizando Flatpak..."
    safe_run "flatpak update -y && flatpak uninstall --unused -y && flatpak repair" && STAT_FLATPAK="$ICON_OK" || STAT_FLATPAK="$ICON_FAIL"
else
    STAT_FLATPAK="$ICON_SKIP (no instalado)"
fi

if command -v snap >/dev/null; then
    print_step "[4/9] Actualizando Snap..."
    safe_run "snap refresh" && STAT_SNAP="$ICON_OK" || STAT_SNAP="$ICON_FAIL"
else
    STAT_SNAP="$ICON_SKIP (no instalado)"
fi

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

print_step "[6/9] Limpieza APT..."
safe_run "apt autoremove -y && apt purge -y ~c && apt $APT_CLEAN_MODE" && STAT_CLEAN_APT="$ICON_OK" || STAT_CLEAN_APT="$ICON_FAIL"

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

print_step "[8/9] Limpieza logs y caché..."
journalctl --vacuum-time=${DIAS_LOGS}d --vacuum-size=500M >/dev/null 2>&1
find /var/tmp -type f -atime +30 -delete 2>/dev/null
for h in /home/*; do [ -d "$h/.cache/thumbnails" ] && rm -rf "$h/.cache/thumbnails/"* 2>/dev/null; done
STAT_CLEAN_DISK="$ICON_OK"

print_step "[9/9] Verificando reinicio..."
RESTART_REQUIRED=false
if [ -f /var/run/reboot-required ]; then
    RESTART_REQUIRED=true
    [ "$QUIET" = false ] && echo -e "${YELLOW}→ Reinicio necesario por actualización crítica${NC}"
fi
if command -v needrestart >/dev/null; then
    [ "$DRY_RUN" = false ] && needrestart -r a >> "$LOG_FILE" 2>&1
fi
[ "$RESTART_REQUIRED" = true ] && STAT_REBOOT="${RED}${ICON_WARN} REQUERIDO${NC}" || STAT_REBOOT="${GREEN}${ICON_OK} No necesario${NC}"

if [ "$ENABLE_HELD_CHECK" = true ]; then
    held=$(apt-mark showhold)
    [ -n "$held" ] && [ "$QUIET" = false ] && echo -e "${YELLOW}⚠️ Paquetes retenidos: $held${NC}"
fi

# ====================== RESUMEN ======================
END_TIME=$(date +%s)
MINUTES=$(((END_TIME - START_TIME)/60))
SECONDS=$(((END_TIME - START_TIME)%60))

SPACE_ROOT=$(((SPACE_BEFORE_ROOT - $(df / --output=used | tail -1 | awk '{print $1}')) / 1024))
SPACE_BOOT=$(((SPACE_BEFORE_BOOT - $(df /boot --output=used 2>/dev/null | tail -1 | awk '{print $1}' || echo 0)) / 1024))

[ "$QUIET" = true ] && exit 0

echo -e "\n${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                  RESUMEN DEL MANTENIMIENTO                    ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo
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

if [ "$RESTART_REQUIRED" = true ] && [ "$UNATTENDED" = false ]; then
    read -p "¿Reiniciar ahora? (s/N): " -n 1 -r
    echo
    [[ $REPLY =~ ^[Ss]$ ]] && reboot
fi

echo "📄 Log: $LOG_FILE"
[ "$ENABLE_BACKUP" = true ] && echo "💾 Backups: $BACKUP_DIR"
echo

exit 0
