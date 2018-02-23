<%!
  import os
  import glob
  from routes import url_for

  prefix = url_for("/")
  path = os.getcwd()
%>
<%
  app_root = "config/plugins/visualizations/"+visualization_name+"/"
  print(app_root)
  app_js = os.path.basename(glob.glob(app_root+"static/js/app.*.js")[0])
  vendor_js = os.path.basename(glob.glob(app_root+"static/js/vendor.*.js")[0])
  manifest_js = os.path.basename(glob.glob(app_root+"static/js/manifest.*.js")[0])
  
  head = "vec2 get_velocity(vec2 p) {\\n  vec2 v = vec2(0., 0.);\\n"
  tail = "\\n  return v;\\n}"
  
  data = list(hda.datatype.dataprovider(
    hda, 
    'line', 
    strip_lines=True, 
    strip_newlines=True ))
  data_text = "\\n".join(data)
  
  # vars =   [k for k in data if 'VARS' in k]
  # vars =   vars[0].replace(" ","").lstrip("VARS:").rstrip(";").split(",") if len(vars) == 1 else None
  # consts = [k for k in data if 'CONSTS' in k]
  # consts = consts[0].replace(" ","").lstrip("CONSTS:").rstrip(";").split(";") if len(consts) == 1 else None
  # params = [k for k in data if 'PARAMS' in k]
  # params = params[0].replace(" ","").lstrip("PARAMS:").rstrip(";").split(";") if len(params) == 1 else None
%>
<html lan"en">
  <head>

    <meta charset="utf-8">
    <meta http-equiv="X-UA-Compatible" content="IE=edge,chrome=1">
    
    <script type="text/javascript" charset="utf-8">
      window.paramsReady = null;
      function parseBIO(text) {
        var lines = text.split("\n");
        var vars = lines.find(w => w.indexOf("VARS:") != -1).replace(/ /g,"").replace("VARS:","").split(",");
        window.variables = vars;
        
        var consts = lines.find(w => w.indexOf("CONSTS:") != -1)
        consts = consts === undefined ? ["undefined"] : consts.replace(/ /g,"").replace("CONSTS:","").split(";");
        consts.forEach(function(w,i){consts[i]=consts[i].split(",")[1].indexOf(".") == -1 ? consts[i]+"." : consts[i]})
        
        var params = lines.find(w => w.indexOf("PARAMS:") != -1)
        var params = params === undefined ? ["undefined"] : params.replace(/ /g,"").replace("PARAMS:","").split(";");
        window.params = params;
        
        if (window.paramsReady)
          window.paramsReady();
        
        var functions =         "float Hillm(float x,float t,float n,float b,float a){\n  return a+(b-a)*(pow(t,n)/(pow(x,n)+pow(t,n)));\n}\n";
        functions = functions + "float hillm(float x,float t,float n,float b,float a){\n  return a+(b-a)*(pow(t,n)/(pow(x,n)+pow(t,n)));\n}\n";
        functions = functions + "float Hillp(float x,float t,float n,float a,float b){\n  return a+(b-a)*(pow(x,n)/(pow(x,n)+pow(t,n)));\n}\n";
        functions = functions + "float hillp(float x,float t,float n,float a,float b){\n  return a+(b-a)*(pow(x,n)/(pow(x,n)+pow(t,n)));\n}\n";
        // TODO: add more functions
        
        var definition = "";
        vars.forEach(function(w,i){definition=definition+"  float "+vars[i]+" = "+(i == 0 || i == 1 ? "p["+i+"]" : "0.0")+";\n"});
        consts.forEach(function(w){definition=definition+"  float "+w.split(",").join(" = ")+";\n"});
        params.forEach(function(w){definition=definition+"  float "+w.split(",")[0]+" = "+(w.split(",")[1].indexOf(".") == -1 ? w.split(",")[1]+"." : w.split(",")[1])+";\n"});
        definition = definition+"\n";
        
        var eqs = lines.filter(w => w.indexOf("EQ:") != -1);
        if(eqs === undefined) {eqs = ["undefined"]} 
        else {eqs.forEach(function(w,i){eqs[i]=eqs[i].replace(/ /g,"").replace("EQ:","")});};
        eqs.forEach(function(w,i){
          // eqs[i]=eqs[i].replace(/(?<![_a-zA-Z\.])([0-9\.]+)(?![_a-zA-Z\.])/g, function(x) {
          eqs[i]=eqs[i].replace(/(.)([0-9\.]+)(?![_a-zA-Z\.])/g, function(whole, first, rest) {
            if (first.match(/[_a-zA-Z\.]/) || rest.indexOf('.') != -1 || first == '.')
              return first + rest;
            return first + rest + '.';
          });
        });
        window.equations = eqs;
        
        if (window.varsReady)
          window.varsReady();
        
        //console.log(eqs);
        eqs.forEach(function(w,i){if (i == 0 || i == 1) definition=definition+"  "+"v["+i+"] = "+eqs[i].split("=")[1]+";\n";});
        
        return functions+'\n${head}'+definition+'${tail}';
      };
    </script>

    <style>
      canvas {
        position: absolute;
      }
      
      body {
        margin: 0;
        padding: 0;
        background: #13294F;
        overflow: hidden;
        position: fixed;
        width: 100%;
        height: 100%;
        left: 0;
        top: 0;
      }
      * {
        box-sizing: border-box;
      }
    </style>
    <title>Field Play</title>
  </head>
  <body>
  
    <script type="text/javascript" charset="utf-8">
      document.onreadystatechange = () => {
        if (document.readyState === 'complete') {
          //var code = '${data_text}';
          var code = parseBIO('${data_text}');
          window.scene.vectorFieldEditorState.code = code;
          window.scene.vectorFieldEditorState.setCode(code);
        }
      };
    </script>
  
    <canvas id="scene"></canvas>
    <div id="app"></div>
    <div id="test">${data}</div>
  
    <script type=text/javascript src=static/js/${manifest_js}></script>
    <script type=text/javascript src=static/js/${vendor_js}></script>
    <script type=text/javascript src=static/js/${app_js}></script>
    
  </body>

</html>
