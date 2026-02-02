# Fedora  
Fedora install &amp; tools  

export GITHUB=https://raw.githubusercontent.com  
or  
export GITHUB=https://gh-proxy.com/raw.githubusercontent.com  

export MAIN=$GITHUB/raidsan/Fedora/refs/heads/main  
export TOOLS_URL=$MAIN/github-tools.sh  
curl -sL $TOOLS_URL | sudo bash -s -- $TOOLS_URL  

## for ollama  
github-tools add $MAIN/ollama-tools/ollama_pull.sh  
github-tools add $MAIN/ollama-tools/ollama_list.sh  
github-tools add $MAIN/ollama-tools/ollama_rm.sh  
github-tools add $MAIN/ollama-tools/ollama_blobs.sh  
