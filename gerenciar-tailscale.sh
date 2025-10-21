#!/bin/bash

# ==============================================================================
#   Script de Gerenciamento do Tailscale para Subnet Router
#   Autor: Gemini (com base na sua solicitação)
#   Data: 17/09/2025
# ==============================================================================

# Cores para o menu
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# --- FUNÇÕES ---

# Função para exibir o menu principal
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

# Função para pausar e esperar o usuário pressionar Enter
press_enter() {
    echo ""
    read -p "Pressione [Enter] para continuar..."
}

# Função 1: Instalar o Tailscale
install_tailscale() {
    clear
    echo -e "${YELLOW}---> Verificando se o Tailscale já está instalado...${NC}"
    if command -v tailscale &> /dev/null; then
        echo -e "${GREEN}Tailscale já está instalado!${NC}"
        VERSION=$(tailscale --version | head -n 1)
        echo "Versão: $VERSION"
        press_enter
        return
    fi

    echo -e "${YELLOW}Tailscale não encontrado. Iniciando instalação...${NC}"
    if ! command -v curl &> /dev/null; then
        echo "O comando 'curl' é necessário. Tentando instalar..."
        apt-get update && apt-get install curl -y
    fi
    
    echo "Baixando e executando o script de instalação oficial..."
    curl -fsSL https://tailscale.com/install.sh | sh

    echo -e "\n${YELLOW}Instalação concluída! Agora vamos conectar à sua rede.${NC}"
    echo "Siga a URL que será exibida para autenticar esta máquina."
    tailscale up
    
    echo -e "\n${GREEN}Máquina conectada à rede Tailscale com sucesso!${NC}"
    press_enter
}

# Função 2: Configurar como Subnet Router
configure_subnet_router() {
    clear
    if ! command -v tailscale &> /dev/null; then
        echo -e "${RED}ERRO: O Tailscale não está instalado. Por favor, execute a opção 1 primeiro.${NC}"
        press_enter
        return
    fi
    
    echo -e "${YELLOW}---> Passo 1: Habilitando o encaminhamento de IP (IP Forwarding)...${NC}"
    echo 'net.ipv4.ip_forward=1' > /etc/sysctl.d/99-tailscale.conf
    echo 'net.ipv6.conf.all.forwarding=1' >> /etc/sysctl.d/99-tailscale.conf
    sysctl -p /etc/sysctl.d/99-tailscale.conf
    echo "Encaminhamento de IP ativado."

    echo -e "\n${YELLOW}---> Passo 2: Descobrindo sua rede local dinamicamente...${NC}"
    DEFAULT_IFACE=$(ip route | grep '^default' | awk '{print $5}' | head -n 1)
    if [ -z "$DEFAULT_IFACE" ]; then
        echo -e "${RED}ERRO: Não foi possível encontrar uma interface de rede padrão ativa.${NC}" >&2
        press_enter
        return
    fi
    echo "Interface de rede principal encontrada: ${GREEN}$DEFAULT_IFACE${NC}"

    LOCAL_NET=$(ip -4 addr show dev "$DEFAULT_IFACE" | grep 'inet' | awk '{print $2}' | head -n 1)
    if [ -z "$LOCAL_NET" ]; then
        echo -e "${RED}ERRO: Não foi possível encontrar o endereço de rede para a interface $DEFAULT_IFACE.${NC}" >&2
        press_enter
        return
    fi
    echo "Rede local a ser anunciada: ${GREEN}$LOCAL_NET${NC}"
    
    echo -e "\n${YELLOW}---> Passo 3: Configurando e anunciando a rota no Tailscale...${NC}"
    tailscale up --advertise-routes=$LOCAL_NET
    
    echo -e "\n\n${YELLOW}========================= ATENÇÃO =========================${NC}"
    echo -e "${YELLOW}A ROTA FOI ANUNCIADA, MAS PRECISA SER APROVADA MANUALMENTE!${NC}"
    echo "1. Acesse o Painel de Administração do Tailscale: https://login.tailscale.com/admin/machines"
    echo "2. Encontre esta máquina na lista."
    echo "3. Clique em '...' (menu) -> 'Edit route settings...' e aprove a rota ${GREEN}$LOCAL_NET${NC}."
    echo -e "${YELLOW}===========================================================${NC}"
    press_enter
}

# Função 3: Testar a configuração
test_subnet_router() {
    clear
    echo -e "${YELLOW}---> Guia para Testar a Configuração do Subnet Router${NC}"
    
    if ! command -v tailscale &> /dev/null; then
        echo -e "${RED}ERRO: O Tailscale não está instalado. Por favor, execute a opção 1 primeiro.${NC}"
        press_enter
        return
    fi

    TS_IP=$(tailscale ip -4)
    DEFAULT_IFACE=$(ip route | grep '^default' | awk '{print $5}' | head -n 1)
    LOCAL_IP=$(ip -4 addr show dev "$DEFAULT_IFACE" | grep 'inet' | awk '{print $2}' | head -n 1 | cut -d'/' -f1)

    echo "O teste deve ser feito a partir de ${YELLOW}OUTRA MÁQUINA${NC} da sua rede Tailscale (ex: seu servidor Zabbix)."
    echo ""
    echo "Informações desta máquina (o Subnet Router):"
    echo -e " - IP na Rede Tailscale: ${GREEN}$TS_IP${NC}"
    echo -e " - IP na Rede Local:    ${GREEN}$LOCAL_IP${NC}"
    echo ""
    echo "========================= INSTRUÇÕES ========================="
    echo "1. Conecte-se (via SSH, por exemplo) à sua outra máquina na rede Tailscale."
    echo "2. Execute o seguinte comando de ping para o IP ${YELLOW}LOCAL${NC} desta máquina:"
    echo ""
    echo -e "   ${GREEN}ping $LOCAL_IP${NC}"
    echo ""
    echo "3. Se o ping funcionar, significa que o roteamento está correto!"
    echo "   Agora você pode tentar pingar sua tomada inteligente ou qualquer outro dispositivo da sua rede local."
    echo "================================================================"
    press_enter
}


# --- LOOP PRINCIPAL DO SCRIPT ---

# Verifica se o script está sendo executado como root (necessário para a maioria das operações)
if [ "$EUID" -ne 0 ]; then 
  echo -e "${RED}ERRO: Por favor, execute este script como root ou usando sudo.${NC}"
  echo "Exemplo: sudo ./gerenciar-tailscale.sh"
  exit 1
fi


while true; do
    show_menu
    read -p "Escolha uma opção [1-4]: " CHOICE

    case $CHOICE in
        1)
            install_tailscale
            ;;
        2)
            configure_subnet_router
            ;;
        3)
            test_subnet_router
            ;;
        4)
            echo "Saindo..."
            break
            ;;
        *)
            echo -e "${RED}Opção inválida. Tente novamente.${NC}"
            sleep 1
            ;;
    esac
done
