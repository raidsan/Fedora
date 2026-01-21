# Fedora  
Fedora install &amp; tools  

export GITHUB=https://raw.githubusercontent.com  
or  
export GITHUB=https://gh-proxy.com/raw.githubusercontent.com  

export MAIN=$GITHUB/raidsan/Fedora/refs/heads/main  

curl -sL $MAIN/github-tools.sh | sudo bash  

## for ollama  
github-tools $MAIN /ollama-tools/ollama_pull.sh | bash  
github-tools $MAIN /ollama-tools/ollama_list.sh | bash  
github-tools $MAIN /ollama-tools/ollama_rm.sh | bash  
github-tools $MAIN /ollama-tools/ollama_blobs.sh | sudo bash  
