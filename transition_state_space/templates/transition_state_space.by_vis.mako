<%!
  import os
  import glob
  import re
  from itertools import chain
  from routes import url_for

  prefix = url_for("/")
  path = os.getcwd()
  
%>
<%
  app_root = "config/plugins/visualizations/"+visualization_name+"/"
  
  data = list(hda.datatype.dataprovider(
    hda, 
    'line', 
    strip_lines=True, 
    strip_newlines=True ))
  data_text = "\\n".join(data)
  
%>
<html lan"en">
  
  <head>
    <title>TSS - Transition State Space</title>
  
    <script type="text/javascript" src="static/vis/dist/vis.js"></script>
  </head>
  
  <style>
    body {
        overflow: hidden;
    }
    #mynetwork {
        margin: 0;
        position: absolute;
        width: 100%;
        height: 100%;
        top: 0;
        right: 0;
        bottom: 0;
        left: 0;
    }
  </style>
  
  <body>
  
    <div id="mynetwork"></div>
  
    <script type="text/javascript">
    
      // create a network
      var container = document.getElementById('mynetwork');
      var parsed_data = vis.network.convertDot('dinetwork { \
          1 [label=x shape=rectangle width=10 height=10 pos="0,0!"] \
          2 [label=x pos="0,1!"] \
          3 [label=x pos="1,0!"] \
          4 [label=x pos="1,1!"] \
           \
          1 -> 1 -> 2 \
          2 -> 3 \
          2 -- 4 \
          2 -> 1 \
          }');
      var data = {
        nodes: parsed_data.nodes,
        edges: parsed_data.edges
      }
      var options = parsed_data.options;
      //options = {
      //  nodes: {
      //    shape: 'box',
      //  }
      //};
      var network = new vis.Network(container, data, options);
    </script>
  
  </body>

</html>
