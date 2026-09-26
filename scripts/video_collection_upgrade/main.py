import os
import re
from flask import Flask, render_template_string, request, jsonify
import yt_dlp

app = Flask(__name__)

# --- CONFIGURATION ---
# Fixed the leading space issue from your screenshot
SOURCE_FOLDER = "/Volumes/Media/Music_Video"
DOWNLOAD_BASE_FOLDER = "./HQ_Downloads"

VIDEO_EXTENSIONS = ('.mkv', '.mp4', '.avi', '.webm', '.flv')

def clean_filename(filename):
    name = os.path.splitext(filename)[0]
    name = re.sub(r'[._\-]', ' ', name)
    return name

def fix_playlist_file_name():
    directory = DOWNLOAD_BASE_FOLDER+'/Playlists/Regional/'
    for filename in os.listdir(directory):
        if os.path.isfile(os.path.join(directory, filename)):
            # New name starts from the 4th character (index 3)
            new_name = filename[5:]
            
            # Define full paths
            old_file = os.path.join(directory, filename)
            new_file = os.path.join(directory, new_name)

            try:
                os.rename(old_file, new_file)
                print(f"Renamed: {filename} -> {new_name}")
            except Exception as e:
                print(f"Error renaming {filename}: {e}")

@app.route('/')
def index():
    files_data = []
    if os.path.exists(SOURCE_FOLDER):
        for root, dirs, files in os.walk(SOURCE_FOLDER):
            if "HQ_Downloads" in root: continue
            for f in files:
                if f.startswith('._') or f.startswith('.'): continue
                if f.lower().endswith(VIDEO_EXTENSIONS):
                    # Use the actual folder name as the category
                    current_category = os.path.basename(root)
                    files_data.append({
                        'original_name': f,
                        'folder_path': root,
                        'clean_name': clean_filename(f),
                        'category': current_category
                    })
    return render_template_string(HTML_TEMPLATE, files=files_data, page='home')

@app.route('/playlist_ui')
def playlist_ui():
    return render_template_string(HTML_TEMPLATE, page='playlist')

@app.route('/search', methods=['POST'])
def search_youtube():
    query = request.json.get('query')
    ydl_opts = {'quiet': True, 'noplaylist': True, 'extract_flat': True}
    try:
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            result = ydl.extract_info(f"ytsearch1:{query} high quality", download=False)
            if 'entries' in result and result['entries']:
                video = result['entries'][0]
                return jsonify({'found': True, 'title': video['title'], 'id': video['id']})
    except Exception as e:
        return jsonify({'found': False, 'error': str(e)})
    return jsonify({'found': False})

@app.route('/download', methods=['POST'])
def download_video():
    video_id = request.json.get('video_id')
    category = request.json.get('category')
    save_path = os.path.join(DOWNLOAD_BASE_FOLDER, category)
    if not os.path.exists(save_path): os.makedirs(save_path)
        
    ydl_opts = {
        'format': 'bestvideo[height<=1080]+bestaudio/best', # Max 1080p
        'outtmpl': f'{save_path}/%(title)s.%(ext)s',
        'merge_output_format': 'mp4',
    }
    try:
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            ydl.download([f'https://www.youtube.com/watch?v={video_id}'])
        return jsonify({'status': 'success'})
    except Exception as e:
        return jsonify({'status': 'error', 'message': str(e)})

@app.route('/download_playlist', methods=['POST'])
def download_playlist():
    url = request.json.get('url')
    category = request.json.get('category')
    save_path = os.path.join(DOWNLOAD_BASE_FOLDER, "Playlists", category)
    
    if not os.path.exists(save_path): os.makedirs(save_path)

    ydl_opts = {
        'format': 'bestvideo[height<=1080]+bestaudio/best', # Constraint: Max 1080p
        'outtmpl': f'{save_path}/%(title)s.%(ext)s',
        'merge_output_format': 'mp4',
        'noplaylist': False,
    }
    try:
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            ydl.download([url])
        return jsonify({'status': 'success'})
    except Exception as e:
        return jsonify({'status': 'error', 'message': str(e)})

# --- UI TEMPLATE WITH NAVIGATION ---
HTML_TEMPLATE = """
<!DOCTYPE html>
<html>
<head>
    <title>Video Collection Manager</title>
    <style>
        body { font-family: 'Segoe UI', sans-serif; background: #f0f2f5; margin: 0; padding: 0; }
        nav { background: #2c3e50; padding: 1rem; display: flex; gap: 20px; box-shadow: 0 2px 5px rgba(0,0,0,0.2); }
        nav a { color: white; text-decoration: none; font-weight: bold; padding: 8px 15px; border-radius: 4px; }
        nav a:hover { background: #34495e; }
        .active { background: #007bff !important; }
        .container { padding: 30px; max-width: 1200px; margin: auto; }
        .card { background: white; padding: 20px; margin-bottom: 15px; border-radius: 8px; box-shadow: 0 2px 5px rgba(0,0,0,0.05); display: flex; align-items: center; gap: 20px; }
        .playlist-box { background: white; padding: 40px; border-radius: 12px; text-align: center; box-shadow: 0 4px 15px rgba(0,0,0,0.1); }
        input[type="text"] { padding: 12px; border: 1px solid #ddd; border-radius: 6px; width: 60%; }
        select { padding: 12px; border-radius: 6px; border: 1px solid #ddd; }
        button { padding: 12px 24px; border: none; border-radius: 6px; background: #28a745; color: white; cursor: pointer; font-weight: bold; }
        button:disabled { background: #ccc; }
        .preview-area { width: 300px; height: 160px; background: #000; border-radius: 6px; overflow: hidden; }
        iframe { width: 100%; height: 100%; border: none; }
    </style>
</head>
<body>
    <nav>
        <a href="/" class="{{ 'active' if page == 'home' else '' }}">Local Folder Scanner</a>
        <a href="/playlist_ui" class="{{ 'active' if page == 'playlist' else '' }}">Playlist Downloader</a>
    </nav>

    <div class="container">
        {% if page == 'home' %}
            <h1>Local NAS Scanner</h1>
            <p>Scanning: <code>{{ files|length }}</code> files in <code>/Volumes/Media/Music_Video</code></p>
            {% for file in files %}
            <div class="card">
                <div style="flex:1">
                    <strong style="display:block">{{ file.original_name }}</strong>
                    <small style="color: #666;">Folder: {{ file.category }}</small>
                </div>
                <div class="preview-area" id="prev-{{ loop.index }}"></div>
                <select id="cat-{{ loop.index }}">
                    <option value="Hindi" {{ 'selected' if file.category == 'Hindi' }}>Hindi</option>
                    <option value="English" {{ 'selected' if file.category == 'English' }}>English</option>
                    <option value="Regional" {{ 'selected' if file.category == 'Regional' }}>Regional</option>
                </select>
                <button onclick="search('{{ file.clean_name | replace("'", "") }}', {{ loop.index }})">Search</button>
                <button id="dl-{{ loop.index }}" disabled onclick="download({{ loop.index }})">Download 1080p</button>
                <input type="hidden" id="id-{{ loop.index }}">
            </div>
            {% endfor %}

        {% else %}
            <div class="playlist-box">
                <h1>YouTube Playlist Downloader</h1>
                <p>Videos will be saved in 1080p quality to your NAS</p>
                <div style="margin-top: 30px; display: flex; flex-direction: column; gap: 15px; align-items: center;">
                    <input type="text" id="playlist-url" placeholder="Paste YouTube Playlist Link Here">
                    <select id="playlist-cat">
                        <option value="Hindi">Hindi</option>
                        <option value="English">English</option>
                        <option value="Regional">Regional</option>
                    </select>
                    <button id="p-btn" onclick="downloadPlaylist()" style="width: 200px; background: #007bff;">Start Download</button>
                    <div id="p-status" style="margin-top: 20px; font-weight: bold;"></div>
                </div>
            </div>
        {% endif %}
    </div>

    <script>
        // Folder Scanner Functions
        async function search(q, idx) {
            const res = await fetch('/search', {method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({query:q})});
            const d = await res.json();
            if(d.found) {
                document.getElementById(`prev-${idx}`).innerHTML = `<iframe src="https://www.youtube.com/embed/${d.id}"></iframe>`;
                document.getElementById(`id-${idx}`).value = d.id;
                document.getElementById(`dl-${idx}`).disabled = false;
            }
        }

        async function download(idx) {
            const id = document.getElementById(`id-${idx}`).value;
            const cat = document.getElementById(`cat-${idx}`).value;
            const btn = document.getElementById(`dl-${idx}`);
            btn.innerText = "Downloading..."; btn.disabled = true;
            await fetch('/download', {method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({video_id:id, category:cat})});
            btn.innerText = "Complete";
        }

        // Playlist Functions
        async function downloadPlaylist() {
            const url = document.getElementById('playlist-url').value;
            const cat = document.getElementById('playlist-cat').value;
            const btn = document.getElementById('p-btn');
            const status = document.getElementById('p-status');

            if(!url) return alert("Please paste a URL");
            
            btn.disabled = true; btn.innerText = "Processing...";
            status.innerText = "Starting background download task... check your terminal for progress.";

            const res = await fetch('/download_playlist', {
                method:'POST', 
                headers:{'Content-Type':'application/json'}, 
                body:JSON.stringify({url: url, category: cat})
            });
            const d = await res.json();
            if(d.status === 'success') {
                status.innerText = "Success! Playlist downloaded to NAS.";
                status.style.color = "green";
            } else {
                status.innerText = "Error occurred. Check terminal.";
                status.style.color = "red";
            }
            btn.disabled = false; btn.innerText = "Start Download";
        }
    </script>
</body>
</html>
"""

if __name__ == '__main__':
    app.run(debug=True, port=5000)
    # fix_playlist_file_name()