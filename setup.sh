#!/bin/bash
# setup.sh - Montagem pesada em /tmp (fora da cota) + JARs salvos na /home
set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JAR_DIR="$PROJECT_ROOT/algorithmJARs"

# Diretório temporário local da máquina (fora da cota da /home)
WORK_DIR="/tmp/$USER/tcc_env"
MINICONDA_DIR="$WORK_DIR/miniconda3"
DEPS_DIR="$WORK_DIR/deps"
M2_REPO="$WORK_DIR/m2_repo"

echo "🚀 Iniciando montagem pesada em $WORK_DIR (fora da cota)..."
mkdir -p "$WORK_DIR" "$DEPS_DIR" "$M2_REPO" "$JAR_DIR"

# 1. Instalar Miniconda3 em /tmp se não existir
if [ ! -d "$MINICONDA_DIR" ]; then
    echo "📦 Baixando e instalando Miniconda em /tmp..."
    wget -q https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O "$WORK_DIR/miniconda.sh"
    bash "$WORK_DIR/miniconda.sh" -b -p "$MINICONDA_DIR"
    rm "$WORK_DIR/miniconda.sh"
fi

export PATH="$MINICONDA_DIR/bin:$PATH"

# 2. Otimizar Conda e aceitar Termos de Serviço
"$MINICONDA_DIR/bin/conda" config --set CONDA_FETCH_THREADS 1 2>/dev/null || true
"$MINICONDA_DIR/bin/conda" config --set solver classic 2>/dev/null || true
"$MINICONDA_DIR/bin/conda" tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main 2>/dev/null || true
"$MINICONDA_DIR/bin/conda" tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r 2>/dev/null || true

# 3. Criar ambiente Conda 'db_env' com OpenJDK 17 e Maven
if ! "$MINICONDA_DIR/bin/conda" env list | grep -q "db_env"; then
    echo "⚙️ Criando ambiente Conda 'db_env'..."
    "$MINICONDA_DIR/bin/conda" create -n db_env python=3.8 postgresql openjdk=17 maven --override-channels -c conda-forge --yes
fi

# 4. Ativar ambiente e instalar PyTorch + libs (cache do pip também em /tmp)
echo "🧠 Instalando PyTorch e dependências Python..."
set +e
source "$MINICONDA_DIR/bin/activate" db_env
set -e

export PIP_CACHE_DIR="$WORK_DIR/pip_cache"
pip install -q torch torchvision torchaudio --extra-index-url https://download.pytorch.org/whl/cu118
pip install -q "sqlalchemy<2.0" pyitlib python-Levenshtein gensim editdistance future pandas numpy psycopg2-binary scikit-learn scipy networkx tqdm pulp

# 5. Clonar repositórios em /tmp/deps (incluindo UniClean e Horizon)
cd "$DEPS_DIR"
echo "📂 Clonando repositórios oficiais em /tmp..."
[ ! -d "LIMA" ] && git clone -q https://github.com/NoSocAlgroc/LIMA.git
[ ! -d "HoloClean" ] && git clone -q https://github.com/HoloClean/HoloClean.git
[ ! -d "UniClean" ] && git clone -q https://github.com/qzkinhit/UniClean-bench-Result.git UniClean
[ ! -d "Horizon" ] && git clone -q https://github.com/D2IP-TUB/Horizon.git
[ ! -d "metanome" ] && git clone -q https://github.com/HPI-Information-Systems/metanome.git
[ ! -d "DCValidity" ] && git clone -q https://github.com/NoSocAlgroc/DCValidity.git

# Instalar requirements específicos do HoloClean, UniClean e Horizon (com fallback seguro)
[ -f "$DEPS_DIR/HoloClean/requirements.txt" ] && pip install -q -r "$DEPS_DIR/HoloClean/requirements.txt" || true
[ -f "$DEPS_DIR/UniClean/requirements.txt" ] && pip install -q -r "$DEPS_DIR/UniClean/requirements.txt" || true
[ -f "$DEPS_DIR/Horizon/requirements.txt" ] && pip install -q -r "$DEPS_DIR/Horizon/requirements.txt" || true

# 6. Configurar Maven para usar /tmp/m2_repo e liberar Lombok no JDK 17
export MAVEN_OPTS="--add-opens jdk.compiler/com.sun.tools.javac.processing=ALL-UNNAMED --add-opens jdk.compiler/com.sun.tools.javac.code=ALL-UNNAMED --add-opens jdk.compiler/com.sun.tools.javac.tree=ALL-UNNAMED --add-opens jdk.compiler/com.sun.tools.javac.util=ALL-UNNAMED"
MVN_CMD="mvn -Dmaven.repo.local=$M2_REPO"

echo "☕ Compilando LIMA..."
cd "$DEPS_DIR/LIMA"
$MVN_CMD clean package -DskipTests -Dmaven.javadoc.skip=true -Dmaven.source.skip=true

echo "☕ Instalando módulos core do Metanome..."
cd "$DEPS_DIR/metanome"
$MVN_CMD clean install -pl algorithm_integration,algorithm_helper,backend,test_helper -am -DskipTests -Dmaven.javadoc.skip=true -Dmaven.source.skip=true

echo "☕ Instalando POM pai + utils (metanome-algorithms) e compilando DCValidity..."
cd "$DEPS_DIR"
[ ! -d "metanome_parent" ] && git clone --depth 1 --filter=blob:none --sparse https://github.com/HPI-Information-Systems/metanome-algorithms.git metanome_parent
cd "$DEPS_DIR/metanome_parent"
git sparse-checkout set utils
$MVN_CMD install -N
cd utils
$MVN_CMD clean install -DskipTests -Dmaven.javadoc.skip=true -Dmaven.source.skip=true

cd "$DEPS_DIR/DCValidity"
for alg in FastDC hydra dcfinder; do
    if [ -d "algorithms/$alg" ]; then
        echo "   -> Compilando $alg..."
        cd "algorithms/$alg"
        $MVN_CMD clean package -DskipTests -Dmaven.javadoc.skip=true -Dmaven.source.skip=true
        cd ../..
        cp "algorithms/$alg/target/$alg-"*.jar "$JAR_DIR/$alg.jar" 2>/dev/null || true
    fi
done

echo ""
echo "✅ Tudo pronto, piá! Ambiente completo com HoloClean, UniClean e Horizon montado."
ls -lh "$JAR_DIR"
echo "👉 Para ativar o ambiente neste terminal, rode:"
echo "   source $MINICONDA_DIR/bin/activate db_env"