#!/bin/bash

# ==============================================================================
#   Script de Gerenciamento do Tailscale para Subnet Router
#   Autor: Gemini (ajustado)
# ==============================================================================

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

show_menu() {
    clear
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${BLUE}     Gerenciador de Tailscale - Subnet Router        ${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    echo ""
    echo -e "${GREEN}1.${NC} Instalar o Tailscale (ou verificar instalação)"
    echo -e "${GREEN}2.${NC} Configurar esta máquina como Subnet Router"
    echo -e "${GREEN}3.${NC} Testar a configuração do Subnet Router"
    echo ""
    echo -e "${RED}4.${NC} Sair"
    echo ""
    echo -e "${BLUE}=====================================================${NC}"
}

press_enter() {
    echo ""
    read -p "Pressione [Enter] para continuar..."
}

install_tailscale() {
    clear
    echo -e "${YELLOW}---> Verificando se o Tailscale já está instalado...${NC}"

    if command -v tailscale &> /dev/null; then
        echo -e "${GREEN}Tailscale já está instalado!${NC}"
        tailscale --version | head -n 1
        press_enter
        return
    fi

    echo -e "${YELLOW}Tailscale não encontrado. Instalando...${NC}"

    if ! command -v curl &> /dev/null; then
        apt-get update && apt-get install curl -y
    fi

    curl -fsSL https://tailscale.com/install.sh | sh

    echo -e "\n${YELLOW}Autenticando...${NC}"
    tailscale up

    echo -e "${GREEN}Tailscale configurado!${NC}"
    press_enter
}

configure_subnet_router() {
    clear

    if ! command -v tailscale &> /dev/null; then
        echo -e "${RED}ERRO: Instale o Tailscale primeiro (opção 1).${NC}"
        press_enter
        return
    fi

    echo -e "${YELLOW}---> Passo 1: Habilitando IP Forwarding...${NC}"
    echo 'net.ipv4.ip_forward=1' > /etc/sysctl.d/99-tailscale.conf
    echo 'net.ipv6.conf.all.forwarding=1' >> /etc/sysctl.d/99-tailscale.conf
    sysctl -p /etc/sysctl.d/99-tailscale.conf

    echo -e "\n${YELLOW}---> Passo 2: Detectando rede local...${NC}"

    DEFAULT_IFACE=$(ip route | grep '^default' | awk '{print $5}' | head -n 1)

    if [ -z "$DEFAULT_IFACE" ]; then
        echo -e "${RED}Erro ao detectar interface padrão.${NC}"
        press_enter
        return
    fi

    echo -e "Interface: ${GREEN}$DEFAULT_IFACE${NC}"

    # Tenta pegar a rede direto (método principal)
    LOCAL_NET=$(ip route | grep "$DEFAULT_IFACE" | grep -v default | awk '{print $1}' | head -n 1)

    # Fallback usando ipcalc se necessário
    if [[ ! "$LOCAL_NET" =~ "/" ]]; then
        echo -e "${YELLOW}Fallback: usando ipcalc...${NC}"

        if ! command -v ipcalc &> /dev/null; then
            echo "Instalando ipcalc..."
            apt-get update && apt-get install ipcalc -y
        fi

        IP_CIDR=$(ip -4 addr show dev "$DEFAULT_IFACE" | grep 'inet ' | awk '{print $2}' | head -n 1)
        LOCAL_NET=$(ipcalc -n "$IP_CIDR" | grep Network | awk '{print $2}')
    fi

    if [ -z "$LOCAL_NET" ]; then
        echo -e "${RED}Erro ao determinar a rede.${NC}"
        press_enter
        return
    fi

    echo -e "Rede detectada: ${GREEN}$LOCAL_NET${NC}"

    echo -e "\n${YELLOW}---> Passo 3: Anunciando rota no Tailscale...${NC}"
    tailscale up --advertise-routes="$LOCAL_NET"

    echo -e "\n${YELLOW}========================= ATENÇÃO =========================${NC}"
    echo "Acesse:"
    echo "https://login.tailscale.com/admin/machines"
    echo ""
    echo "E APROVE a rota: ${GREEN}$LOCAL_NET${NC}"
    echo -e "${YELLOW}===========================================================${NC}"

    press_enter
}

test_subnet_router() {
    clear
    echo -e "${YELLOW}---> Teste do Subnet Router${NC}"

    if ! command -v tailscale &> /dev/null; then
        echo -e "${RED}Instale o Tailscale primeiro.${NC}"
        press_enter
        return
    fi

    TS_IP=$(tailscale ip -4)
    DEFAULT_IFACE=$(ip route | grep '^default' | awk '{print $5}' | head -n 1)
    LOCAL_IP=$(ip -4 addr show dev "$DEFAULT_IFACE" | grep 'inet ' | awk '{print $2}' | cut -d'/' -f1)

    echo -e "IP Tailscale: ${GREEN}$TS_IP${NC}"
    echo -e "IP Local:     ${GREEN}$LOCAL_IP${NC}"

    echo ""
    echo "Teste de outra máquina:"
    echo -e "${GREEN}ping $LOCAL_IP${NC}"

    press_enter
}

if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Execute como root (sudo).${NC}"
    exit 1
fi

while true; do
    show_menu
    read -p "Escolha [1-4]: " CHOICE

    case $CHOICE in
        1) install_tailscale ;;
        2) configure_subnet_router ;;
        3) test_subnet_router ;;
        4) break ;;
        *) echo -e "${RED}Opção inválida${NC}" && sleep 1 ;;
    esac
done
