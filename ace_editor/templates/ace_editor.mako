<%!
import os
from routes import url_for

prefix = url_for("/")
path = os.getcwd()

%>
<%
data = "\n".join(list(hda.datatype.dataprovider( hda, 'line', comment_char=none, provide_blank=True, strip_lines=False, strip_newlines=True )))
#print data
%>
<html lan"en">
  <head>

    <meta charset="utf-8">
    <meta http-equiv="X-UA-Compatible" content="IE=edge,chrome=1">

    <title>Ace Editor</title>

    <style type="text/css" media="screen">
        body {
                overflow: hidden;
        }
        #editor {
            margin: 0;
            position: absolute;
            top: 40px;
            right: 0;
            bottom: 0;
            left: 0;
        }
        .button {
            background-color: #4CAF50; /* Green */

            border-color: #000;
            border-radius: 3px;
            border-style: solid;
            border-width: 1px;
            box-sizing: border-box;
            color: white;
            border: none;
            font-size: 12px;
            font-weight: 400;
            font-family: sans-serif;
            cursor: pointer;

            position: absolute;
            top: 2px;
            height: 36px;
        }
        .button:hover {
            background-color: #2c4330; /* #2c3143; */
        }
        #save_btn {
            left: 2px;
        }
        #undo_btn {
            left: 134px;
        }
        #redo_btn {
            left: 186px;
        }
        #wrap_btn {
            left: 236px;
        }
    </style>
    <script type="application/javascript" src="https://ajax.googleapis.com/ajax/libs/jquery/2.0.0/jquery.min.js"></script>
	
  </head>

  <body  type="text/plain" charset="utf-8">
  	<script type="text/javascript" charset="utf-8">
        var hist_id = null;
      
        $(function() {
            var address = '${prefix}/history/current_history_json';
            $.get(address, function(resp) {
                if (resp && resp.id)
                    hist_id = resp.id;
            });
            $('#undo_btn').on('click', function() { ace.edit('editor').undo(); });
            $('#redo_btn').on('click', function() { ace.edit('editor').redo(); });
            $('#wrap_btn').on('click', function() { ace.edit('editor').getSession().setUseWrapMode(!ace.edit('editor').getSession().getUseWrapMode()); });
      
            $('#save_btn').on('click', function() {
                var cont = ace.edit('editor').getValue();
                var dInputs = {
                    dbkey: '?',
                    file_type: 'auto',
                    'files_0|type': 'upload_dataset',
                    'files_0|space_to_tab': null,
                    'files_0|to_posix_lines': 'Yes'
                };
          
                var formData = new FormData();
                formData.append('tool_id', 'upload1');
                formData.append('history_id', hist_id);
                formData.append('inputs', JSON.stringify(dInputs));
                formData.append('files_0|file_data', new Blob([cont], {type: 'text/plain'}), 'Text edit on data '+$('#editor').attr('file-hid') );
          
                $.ajax({
                    url: '${prefix}/api/tools',
                    data: formData,
                    processData: false,
                    contentType: false,
                    type: 'POST',
                    success: function (resp) {
                        window.setTimeout(function() {
                            window.parent.$('#history-refresh-button').trigger('click');
                        }, 3000);
                    }
                });
            });
        });
	</script>

    <input class="button" type="button" id="save_btn" value="Save modifications" />
    <input class="button" type="button" id="undo_btn" value="Undo" />
    <input class="button" type="button" id="redo_btn" value="Redo" />
    <input class="button" type="button" id="wrap_btn" value="Word wrap" />
    <div id="editor" file-name=${hda.name} file-hid=${hda.hid} >${data|x}</div>
	
    <script src="static/ace-builds/src-noconflict/ace.js" type="text/javascript" charset="utf-8"></script>
    <script>
    		var editor = ace.edit("editor");
    		editor.setTheme("ace/theme/twilight");
    		editor.getSession().setMode("ace/mode/python");
    		editor.getSession().setTabSize(4);
                editor.setShowPrintMargin(false);
    		editor.setHighlightActiveLine(true);
    		editor.resize();
    </script>

  </body>

</html>
