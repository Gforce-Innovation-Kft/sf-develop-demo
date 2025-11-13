FROM ubuntu:22.04

# Avoid warnings by switching to noninteractive
ENV DEBIAN_FRONTEND=noninteractive

# Configure apt and install packages
RUN apt-get update \
    && apt-get -y install --no-install-recommends \
    apt-utils \
    dialog \
    ca-certificates \
    curl \
    wget \
    git \
    gnupg2 \
    lsb-release \
    apt-transport-https \
    software-properties-common \
    build-essential \
    openssl \
    vim \
    nano \
    unzip \
    zip \
    xz-utils \
    # XML and JSON processing tools
    xmlstarlet \
    jq \
    # Additional utilities
    less \
    htop \
    tree \
    # Zsh and related
    zsh \
    fonts-powerline \
    locales \
    2>&1

# Set locale
RUN locale-gen en_US.UTF-8
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

# Install Node.js 20.x
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs

# Install Java (OpenJDK 17)
RUN apt-get install -y openjdk-17-jdk

# Install Salesforce CLI
RUN npm install -g @salesforce/cli

# Create vscode user with sudo privileges
RUN useradd -m -s /bin/zsh -u 1000 vscode \
    && apt-get install -y sudo \
    && echo vscode ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/vscode \
    && chmod 0440 /etc/sudoers.d/vscode

# Switch to vscode user
USER vscode
WORKDIR /home/vscode

# Install SF CLI autocomplete for zsh
RUN sf autocomplete zsh

# Install Oh My Zsh
RUN sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended

# Install Powerlevel10k theme
RUN git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k

# Install Zsh plugins
RUN git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions \
    && git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting \
    && git clone https://github.com/zsh-users/zsh-completions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-completions

# Copy Zsh configuration
COPY --chown=vscode:vscode .devcontainer/.zshrc /home/vscode/.zshrc
COPY --chown=vscode:vscode .devcontainer/.p10k.zsh /home/vscode/.p10k.zsh

# Create directories for Salesforce CLI
RUN mkdir -p /home/vscode/.sfdx /home/vscode/.sf /home/vscode/.config

# Set environment variables
ENV SFDX_CONTAINER_MODE=true
ENV SFDX_DISABLE_DNS_CHECK=true
ENV SF_AUTOUPDATE_DISABLE=true

# Switch back to dialog for any ad-hoc use of apt-get
ENV DEBIAN_FRONTEND=dialog

# Set the default shell to zsh
SHELL ["/bin/zsh", "-c"]

# Verify installations
RUN echo "Node version: $(node --version)" \
    && echo "NPM version: $(npm --version)" \
    && echo "Java version: $(java -version 2>&1 | head -n 1)" \
    && echo "SF CLI version: $(sf version)" \
    && echo "jq version: $(jq --version)" \
    && echo "xmlstarlet version: $(xmlstarlet --version)"

WORKDIR /workspace

CMD ["/bin/zsh"]
