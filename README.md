# Fedora  
Fedora install &amp; tools  

export GITHUB=https://raw.githubusercontent.com  
or  
export GITHUB=https://gh-proxy.com/raw.githubusercontent.com  

export MAIN=$GITHUB/raidsan/Fedora/refs/heads/main  
export TOOLS_URL=$MAIN/github-tools.sh  
curl -sL $TOOLS_URL | sudo bash -s -- $TOOLS_URL  

## for ollama  
sudo github-tools add $MAIN/ollama-tools/ollama_pull.sh  
sudo github-tools add $MAIN/ollama-tools/ollama_list.sh  
sudo github-tools add $MAIN/ollama-tools/ollama_rm.sh  
sudo github-tools add $MAIN/ollama-tools/ollama_blobs.sh  
