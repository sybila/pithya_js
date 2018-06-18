<%!
  import os
  import glob
  import re
  from itertools import chain
  from routes import url_for

  prefix = url_for("/")
  path = os.getcwd()
  
  def replace_consts(text, l):
    if l is None: return text
    for i in l:
      text = re.sub(r"(?<![A-Za-z0-9_])"+i[0]+"(?![A-Za-z0-9_])", i[1], text)
    return text
    
  def replace_params(text, l):
    if l is None: return text
    for i in l:
      text = re.sub(r"(?<![A-Za-z0-9_])"+i[0]+"(?![A-Za-z0-9_])", "params['"+i[0]+"']", text)
    return text
    
  def replace_vars(text, l):
    if l is None: return text
    for i, v in enumerate(l):
      text = re.sub(r"(?<![A-Za-z0-9_])"+v+"(?![A-Za-z0-9_])", "vars['"+v+"']", text)
    return text
    
  def repair_approx(text):
    return re.sub(r'(Approx\([^)]+)\)\(([^)]+)(\))', '\\1,[\\2]\\3', text)
%>
<%
  app_root = "config/plugins/visualizations/"+visualization_name+"/"
  
  ## list of string lines of input bio file
  data = list(hda.datatype.dataprovider(
    hda, 
    'line', 
    strip_lines=True, 
    strip_newlines=True ))
    
  ## all lines joined into one structured string (keeping all newlines)
  data_text = "\\n".join(data)
  
  ## path to Approximation tool written in Java
  approx_path = '/home/shiny/pithya-gui/core/bin/pithyaApproximation'
  ## unique name of resulting output file (should be unique for every file from personal history)
  output_data = '/tmp/'+hda.name+".hid_"+str(hda.id)+".id_"+str(hda.hid)+".approx.bio"
  ## if this input were approximated before and the output is still in tmp the approximation will be skipped
  if not os.path.isfile(output_data):
    print("## Approximation needed !!!")
    cmd = "echo '{}' | {} > '{}'".format(data_text,approx_path,output_data)
    os.system( cmd )
  with open(output_data) as f: approx_data = [line.rstrip('\n') for line in f]
    
  ## parssing of bio file format to python structures (later used in JS)
  vars =   [k for k in approx_data if re.match('^VARS:',k)]
  vars =   vars[0].replace(" ","").replace("VARS:",'').rstrip(";").split(",") if len(vars) == 1 else None
  consts = [k for k in approx_data if re.match('^CONSTS:',k)]
  consts = chain(*[k.replace(" ","").replace("CONSTS:",'').rstrip(";").split(";") for k in consts]) if len(consts) > 0 else None
  consts = [k.split(',') for k in consts] if consts else None
  params = [k for k in approx_data if re.match('^PARAMS:',k)]
  params = chain(*[k.replace(" ","").replace("PARAMS:",'').rstrip(";").split(";") for k in params]) if len(params) > 0 else None
  params = [k.split(',') for k in params] if params else None
  eqs =    [k.replace(' ','').replace("EQ:","").rstrip(";") for k in approx_data if re.match('^EQ:',k)]
  eqs =    [repair_approx(k) for k in eqs] if eqs else None
  eqs =    [replace_consts(k, consts) for k in eqs] if eqs else None
  eqs =    [replace_params(k, params) for k in eqs] if eqs else None
  eqs =    ["function(vars,params){return "+(replace_vars(k, vars).split('=')[1])+";}" for k in eqs] if eqs else None
  thrs =   [k.replace(' ','').replace("THRES:","").rstrip(";") for k in approx_data if re.match('^THRES:',k)]
  thrs =   {k.split(':')[0] : k.split(':')[1].split(',') for k in thrs} if thrs else None

  if params is None: params = []
  
%>
<html lan"en">
  
  <head>
    <title>Model Explorer</title>
    <meta charset="utf-8">
    <meta http-equiv="X-UA-Compatible" content="IE=edge,chrome=1">
    <script src="http://d3js.org/d3.v4.min.js"></script>
    
    <script type="text/javascript" charset="utf-8">
      // definition of functions used in bio files so there is no need to transorm them 
      function Hillm(x,t,n,b,a) {
        return a+(b-a)*(Math.pow(t,n)/(Math.pow(x,n)+Math.pow(t,n)));
      };
      hillm = Hillm;
      function Hillp(x,t,n,a,b) {
        return a+(b-a)*(Math.pow(x,n)/(Math.pow(x,n)+Math.pow(t,n)));
      };
      hillp = Hillp;
      function Approx(s,ramps) {
        if(s <= ramps[0][0]) return(ramps[0][1])
        if(s >= ramps[ramps.length-1][0]) return(ramps[ramps.length-1][1])
        for(var i = 1;  i < ramps.length; i++) {
          a = ramps[i-1]
          b = ramps[i]
          if(s >= a[0] && s <= b[0]) 
            return((b[0]-a[0]) > 0 ? a[1]+(s-a[0])/(b[0]-a[0])*(b[1]-a[1]) : a[1])
        }
      }
      
      // dynamicly (in mako style) fills dictionary with equations parsed from bio file for using in JS code
      functions = {
      % for ind,eq in enumerate(eqs):
        '${vars[ind]}':${eq|n},
      % endfor
      };
      // creates one structure containing all important from bio file for JS code
      window.bio = {'thrs': ${thrs}, 'vars': ${vars}, 'eqs': functions, 'params': ${params}};
      //console.log(window.bio.thrs);
      
      // SPECIAL DEFINITIONS
      Set.prototype.difference = function(setB) {
          var difference = new Set(this);
          for (var elem of setB) {
              difference.delete(elem);
          }
          return difference;
      };
      d3.selection.prototype.moveUp = function() {
          return this.each(function() {
              this.parentNode.appendChild(this);
          });
      };
      d3.selection.prototype.first = function() {
        return d3.select(this[0][0]);
      };
      d3.selection.prototype.last = function() {
        var last = this.size() - 1;
        return d3.select(this[0][last]);
      };
      function parsing_to_string(x) {
        if(Object.values(x).length > 0) {
          var result = Number.parseFloat(Object.values(x)[0]).toFixed(2).toString();
          for(var i = 1; i < Object.values(x).length; i++) {
            result += " "+Number.parseFloat(Object.values(x)[i]).toFixed(2).toString();
          }
          return result;
        } else return "";
      };
    </script>

    <link rel="stylesheet" type="text/css" href="static/css/bootstrap-reboot.css">
    <link rel="stylesheet" type="text/css" href="static/css/ion.rangeSlider.css">
    <link rel="stylesheet" type="text/css" href="static/css/ion.rangeSlider.skinShiny.css">
    <link rel="stylesheet" type="text/css" href="static/css/simplex2.css">
    <link rel="stylesheet" type="text/css" href="static/css/style.css">
    <!--style>
      body {
        background-color: white;
        margin: 0;
        font-family: sans-serif;
        font-size: 18px;
      }
      #cont_VF {
        pointer-events: all;
      }
      #zoomObject_VF {
      }
      .vector_VF { 
        fill: none;
        vector-effect: non-scaling-stroke; 
      }
      .axis {
        font-size: 15px;
      }
      .widget_panel {
        position: absolute;
        //top: 10px;
        left: 560px;
        //display: flex;
        //flex-direction: column;
        height: 100%;
        width: 250px;
        
      }
      #resetZoomBtn_VF {
        position: absolute;
        top: 10px;
      }
      #resetReachBtn_VF {
        position: absolute;
        top: 40px;
      }
      #elongateReachBtn_VF {
        position: absolute;
        top: 40px;
        left: 80px;
      }
      #infoPanel_VF {
        position: absolute;
        top: 70px;
        flex-grow: 1;
      }
      #x_axis_div {
        position: absolute;
        top: 160px;
        width: 90px;
      }
      #y_axis_div {
        position: absolute;
        top: 160px;
        width: 90px;
        left: 100px;
      }
      #slidecontainer_VF {
        position: absolute;
        top: 200px;
      }
      #inputs_div_VF {
        position: absolute;
        top: 450px;
      }
      
      #cont {
        pointer-events: all;
      }
      #zoomObject {
      }
      .loop {
        vector-effect: non-scaling-stroke; 
      }
      .transition { 
        vector-effect: non-scaling-stroke; 
      }
      .states {
        vector-effect: non-scaling-stroke; 
      }
      #resetZoomBtn {
        position: absolute;
        top: 10px;
      }
      #resetReachBtn {
        position: absolute;
        top: 40px;
      }
      #infoPanel {
        position: absolute;
        top: 70px;
        flex-grow: 1;
      }
      #x_axis_div {
        position: absolute;
        top: 160px;
        width: 90px;
      }
      #y_axis_div {
        position: absolute;
        top: 160px;
        width: 90px;
        left: 100px;
      }
      #slidecontainer {
        position: absolute;
        top: 200px;
      }
      #inputs_div {
        position: absolute;
        top: 450px;
      }
    </style-->
  </head>
    
  <body>
    <div class="widget_panel">
      <button id="resetZoomBtn_VF">Unzoom</button>
      <button id="resetReachBtn_VF">Deselect</button>
      <button id="elongateReachBtn_VF">Elongate</button>
      <textarea id="infoPanel_VF" rows="${len(vars)+2}" cols="35" wrap="off" disabled></textarea>
      <!-- dynamicly adds sliders with labels for parameters and variables (if more than 2 vars are present) in mako style -->
      % if len(vars) > 2 or len(params) > 0:
        <div id="slidecontainer_VF">
        % if len(vars) > 2:
        <hr>
        % for val in vars:
          <% 
          min_val  = min(map(float,thrs[val]))
          max_val  = max(map(float,thrs[val]))
          step_val = abs(max_val-min_val)*0.01
          %>
          % if val == vars[0] or val == vars[1]:
          <div id="slider_${val}_wrapper_VF" hidden>
          % else:
          <div id="slider_${val}_wrapper_VF">
          % endif
            var. ${val}: <span id="text_${val}_VF"></span><br>
            <input type="range" min=${min_val} max=${max_val} value=${min_val} step=${step_val} class="slider" id="slider_${val}_VF">
          </div>
        % endfor
        % endif
        % if len(params) > 0:
        <hr>
        % for val in params:
          <% 
          min_val  = float(val[1])
          max_val  = float(val[2])
          step_val = abs(max_val-min_val)*0.001
          %>
          par. ${val[0]}: <span id="text_${val[0]}"></span><br>
          <input type="range" min=${min_val} max=${max_val} value=${min_val} step=${step_val} class="slider" id="slider_${val[0]}"><br>
        % endfor
        % endif
        </div>
      % endif
      <div id="inputs_div_VF">
        <hr>
        arrows count: <span id="text_gridSize_VF"></span><br>
        <input type="range" min=10 max=100 value=25 step=1 class="slider" id="input_gridSize_VF"><br>
        derivative scale: <span id="text_dt_VF"></span><br>
        <input type="range" min=0.01 max=1 value=1 step=0.01 class="slider" id="input_dt_VF"><br>
        colouring threshold: <span id="text_color_thr_VF"></span><br>
        <input type="range" min=0 max=0.1 value=0.05 step=0.01 class="slider" id="input_color_thr_VF"><br>
        colouring orientation<br>
        <select id="input_color_style_VF">
          <option value="both">both</option>
          <option value="vertical">vertical</option>
          <option value="horizontal">horizontal</option>
          <option value="none">none</option>
        </select><br>
      </div>
      
      <button id="resetZoomBtn">Unzoom</button>
      <button id="resetReachBtn">Deselect</button>
      <textarea id="infoPanel" rows="${len(vars)+1}" cols="35" wrap="off" disabled></textarea>
      <!-- dynamicly adds sliders with labels for parameters and variables (if more than 2 vars are present) in mako style -->
      <div id="x_axis_div">
        X axis<br>
        <select name="xAxis" id="x_axis" style="width:90px" required>
          % for val in vars:
            % if val == vars[0]:
              <option value="${val}" selected>${val}</option>
            % else:
              <option value="${val}">${val}</option>
            % endif
          % endfor
        </select>
      </div>
      <div id="y_axis_div">
        Y axis<br>
        <select name="yAxis" id="y_axis" style="width:90px" required>
          % for val in vars:
            % if len(vars) > 1 and val == vars[1]:
              <option value="${val}" selected>${val}</option>
            % else:
              <option value="${val}">${val}</option>
            % endif
          % endfor
        </select>
      </div>
      % if len(vars) > 2 or len(params) > 0:
        <div id="slidecontainer">
        % if len(vars) > 2:
        <hr>
        % for val in vars:
          <% 
          min_val  = min(map(float,thrs[val]))
          max_val  = max(map(float,thrs[val]))
          step_val = abs(max_val-min_val)*0.01
          %>
          % if val == vars[0] or val == vars[1]:
          <div id="slider_${val}_wrapper" hidden>
          % else:
          <div id="slider_${val}_wrapper">
          % endif
            var. ${val}: <span id="text_${val}"></span><br>
            <input type="range" min=${min_val} max=${max_val} value=${min_val} step=${step_val} class="slider" id="slider_${val}">
          </div>
        % endfor
        % endif
        </div>
      % endif
      <div id="inputs_div">
        <hr>
        colouring orientation<br>
        <select id="input_color_style">
          <option value="both">both</option>
          <option value="vertical">vertical</option>
          <option value="horizontal">horizontal</option>
          <option value="none">none</option>
        </select><br>
      </div>
    </div>
    
    <script type="text/javascript" charset="utf-8">
    
var xDim = document.getElementById("x_axis").value,
    yDim = document.getElementById("y_axis").value,
    thrs = window.bio.thrs,
    params = {},
    dt_VF = Number(d3.select("#input_dt_VF").property("value")),
    traj_dt_VF = 0.1,
    color_style_VF = d3.select("#input_color_style_VF").property("value"),
    color_thr_VF = Number(d3.select("#input_color_thr_VF").property("value")),
    gridSize_VF = Number(d3.select("#input_gridSize_VF").property("value")),
    
    multiarr = [],
    color_style = document.getElementById("input_color_style").value;

// initial values according to the sliders setting
window.bio.params.map(x => params[x[0]] = x[1]);
    
// iteratively adds event listener for varaible sliders (according to index)
% if len(vars) > 2:
  % for val in vars:
      (function(i) {
          d3.select("#text_"+i+"_VF").html(d3.select("#slider_"+i+"_VF").property("value"));
          d3.select("#slider_"+i+"_VF").on("input", function() {
              d3.select("#text_"+i+"_VF").html(this.value);
              zoomed_VF();
          })
      })('${val}');
  % endfor
% endif

// iteratively adds event listener for parameter sliders (according to index)
% if len(params) > 0:
  % for val in params:
      (function(i) {
          d3.select("#text_"+i[0]).html(d3.select("#slider_"+i[0]).property("value"));
          d3.select("#slider_"+i[0]).on("input", function() {
              d3.select("#text_"+i[0]).html(this.value);
              // fill parameters with current values
              params[i[0]] = Number(d3.select("#slider_"+i[0]).property("value")); // according to slider for parameters
              zoomed_VF();
              
              compute_tss();
              transform_tss();
              draw();
              zoomed();
              if(reach_start !== null) handleMouseClick(null,reach_start);
          })
      })(${val});
  % endfor
% endif

// sets text value for slider of arrows_count and adds event listener for change of slider
d3.select("#text_gridSize_VF").html(d3.select("#input_gridSize_VF").property("value"));
d3.select('#input_gridSize_VF').on("input", function() {
  d3.select("#text_gridSize_VF").html(this.value);
  gridSize_VF = Number(this.value);
  zoomed_VF();
});

// sets text value for slider of derivative_scale and adds event listener for change of slider
d3.select("#text_dt_VF").html(d3.select("#input_dt_VF").property("value"));
d3.select('#input_dt_VF').on("input", function() {
  d3.select("#text_dt_VF").html(this.value);
  dt_VF = Number(this.value);
  zoomed_VF();
});

// sets text value for slider of colouring_threshold and adds event listener for change of slider
d3.select("#text_color_thr_VF").html(d3.select("#input_color_thr_VF").property("value"));
d3.select('#input_color_thr_VF').on("input", function() {
  d3.select("#text_color_thr_VF").html(this.value);
  color_thr_VF = Number(this.value);
  zoomed_VF();
});

// adds event listener for change of colouring_orientation
d3.select('#input_color_style_VF').on("input", function() {
  color_style_VF = this.value;
  zoomed_VF();
});

// event listener for change of selectected dimension for X axis
d3.select("#x_axis").on("change", function() {
  var other = d3.select("#y_axis").property("value");
  if(this.value == other) {
    d3.select("#y_axis").property('value',xDim);
    yDim = xDim;
  } else {
    d3.select("#slider_"+xDim+"_wrapper_VF").attr("hidden",null);
  }
  xDim = this.value;
  d3.select("#slider_"+this.value+"_wrapper_VF").attr("hidden","hidden");
  resettedZoom_VF();
  
  resettedZoom();
  transform_tss();
  draw();
  if(reach_start !== null) handleMouseClick(null,reach_start);
});

// event listener for change of selectected dimension for Y axis
d3.select("#y_axis").on("change", function() {
  var other = d3.select("#x_axis").property("value");
  if(this.value == other) {
    d3.select("#x_axis").property('value',yDim);
    xDim = yDim;
  } else {
    d3.select("#slider_"+yDim+"_wrapper_VF").attr("hidden",null);
  }
  yDim = this.value;
  d3.select("#slider_"+this.value+"_wrapper_VF").attr("hidden","hidden");
  resettedZoom_VF();
  
  resettedZoom();
  transform_tss();
  draw();
  if(reach_start !== null) handleMouseClick(null,reach_start);
});

// event listeners for buttons
d3.select('#resetReachBtn_VF')
    .on("click", resettedReach_VF);
    
d3.select('#elongateReachBtn_VF')
    .on("click", elongate_VF);

d3.select('#resetZoomBtn_VF')
    .on("click", resettedZoom_VF);


// iteratively adds event listener for varaible sliders (according to index)
% if len(vars) > 2:
  % for val in vars:
      (function(i) {
          d3.select("#text_"+i).html(d3.select("#slider_"+i).property("value"));
          d3.select("#slider_"+i).on("input", function() {
              d3.select("#text_"+i).html(this.value);
              
              transform_tss();
              draw();
              zoomed();
              if(reach_start !== null) handleMouseClick(null,reach_start);
          })
      })('${val}');
  % endfor
% endif

// adds event listener for change of colouring_orientation
d3.select('#input_color_style').on("input", function() {
  color_style = this.value;
  transform_tss();
  draw();
  zoomed();
  if(reach_start !== null) handleMouseClick(null,reach_start);
});

d3.select('#resetReachBtn')
    .on("click", resettedReach);

d3.select('#resetZoomBtn')
    .on("click", resettedZoom);
    

//###################################################  

var width = 550,
    height = 550,
    margin = { top: 10, right: 10, bottom: 50, left: 50 },
    arrowlen = 3,
    noColor = "transparent",
    reachColor_TS = "rgba(65, 105, 225, 0.6)", // "royalblue with opacity"
    reachColor_VF = "royalblue",
    neutral_col = "black",
    positive_col = "darkgreen",
    negative_col = "red",
    reach_start_VF = null,
    reach_end_VF = null,
    trajectory_VF = "",
    trajectory_VF_length = 1000,
    transWidth_VF = 2,
    selfloopWidth_VF = 4,
    vectors_VF = [],
    zoomObject_VF = d3.zoomIdentity,
    
    normalStrokeWidth = 1,
    hoverStrokeWidth = 4,
    transWidth = 2,
    selfloopWidth = 4,
    reach_start = null;
    statedata = {},
    transdata = [],
    trans = {},
    trans_dir = {},
    zoomObject = d3.zoomIdentity;

// d3 objects definitions
var xScale_VF = d3.scaleLinear()
              .domain([d3.min(thrs[xDim],parseFloat),
                       d3.max(thrs[xDim],parseFloat)])
              .range([margin.left, width - margin.right]);

var yScale_VF = d3.scaleLinear()
              .domain([d3.min(thrs[yDim],parseFloat),
                       d3.max(thrs[yDim],parseFloat)])
              .range([height - margin.bottom, margin.top]);


var brushX_VF = d3.brushX()
    .extent([[margin.left, 0], [width-margin.right, margin.bottom]])
    .on("end", brushedX_VF),
    
    brushY_VF = d3.brushY()
    .extent([[-margin.left, margin.top], [0, height-margin.bottom]])
    .on("end", brushedY_VF);

var zoom_VF = d3.zoom()
    .scaleExtent([0.1, 100000])   // TODO: better specification
    //.translateExtent([[0,0],[width,height]])
    .on("zoom", zoomed_VF);
          
var svg_VF = d3.select("body").append("svg")
    .attr("width", width)
    .attr("height", height);

var container_VF = svg_VF.append("g")
    .attr("id","cont_VF")
    //.attr("transform", "translate("+(margin.left)+","+(margin.top)+")")
    .call(zoom_VF);
        
var defs_VF = svg_VF.append("svg:defs");
defs_VF.append("svg:marker")
		.attr("id", "neutralArrow")
		.attr("viewBox", "0 "+(-0.5*arrowlen)+" "+arrowlen+" "+arrowlen)
		.attr("refX", 0.5*arrowlen)
		.attr("refY", 0)
		.attr("markerWidth", arrowlen)
		.attr("markerHeight", arrowlen)
		.attr("orient","auto")
    .append("svg:path")
      .attr("fill", neutral_col)
			.attr("d", "M0,"+(-0.5*arrowlen)+" L"+arrowlen+",0 L0,"+(0.5*arrowlen))
			.attr("class","arrowHead");
defs_VF.append("svg:marker")
		.attr("id", "positiveArrow")
		.attr("viewBox", "0 "+(-0.5*arrowlen)+" "+arrowlen+" "+arrowlen)
		.attr("refX", 0.5*arrowlen)
		.attr("refY", 0)
		.attr("markerWidth", arrowlen)
		.attr("markerHeight", arrowlen)
		.attr("orient","auto")
    .append("svg:path")
      .attr("fill", positive_col)
			.attr("d", "M0,"+(-0.5*arrowlen)+" L"+arrowlen+",0 L0,"+(0.5*arrowlen))
			.attr("class","arrowHead");
defs_VF.append("svg:marker")
		.attr("id", "negativeArrow")
		.attr("viewBox", "0 "+(-0.5*arrowlen)+" "+arrowlen+" "+arrowlen)
		.attr("refX", 0.5*arrowlen)
		.attr("refY", 0)
		.attr("markerWidth", arrowlen)
		.attr("markerHeight", arrowlen)
		.attr("orient","auto")
    .append("svg:path")
      .attr("fill", negative_col)
			.attr("d", "M0,"+(-0.5*arrowlen)+" L"+arrowlen+",0 L0,"+(0.5*arrowlen))
			.attr("class","arrowHead");
defs_VF.append("svg:marker")
		.attr("id", "reachArrow")
		.attr("viewBox", "0 "+(-0.5*arrowlen)+" "+arrowlen+" "+arrowlen)
		.attr("refX", 0.5*arrowlen)
		.attr("refY", 0)
		.attr("markerWidth", arrowlen)
		.attr("markerHeight", arrowlen)
		.attr("orient","auto")
    .append("svg:path")
      .attr("fill", reachColor_VF)
			.attr("d", "M0,"+(-0.5*arrowlen)+" L"+arrowlen+",0 L0,"+(0.5*arrowlen))
			.attr("class","reachArrowHead");

var xLabel_VF = svg_VF.append("text")
    .attr("id", "xLabel_VF")
    .attr("class", "label")
    .attr("x", width*0.5)
    .attr("y", height-10)
    .attr("stroke", "black")
    .text(function() { return xDim; });
var ylabel_VF = svg_VF.append("text")
    .attr("id", "ylabel_VF")
    .attr("class", "label")
    .attr("transform", "rotate(-90)")
    .attr("x", -width*0.5)
    .attr("y", 15)
    .attr("stroke", "black")
    .text(function() { return yDim; });

var bottomPanel_VF = svg_VF.append("g")
    .attr("id", "bPanel_VF")
    .attr("class", "panel")
    .attr("transform", "translate("+(0)+","+(height-margin.bottom)+")");
    
var xAxis_VF = d3.axisBottom(xScale_VF);
var gX_VF = bottomPanel_VF.append("g")
    .attr("id", "xAxis_VF")
    .attr("class", "axis")
    .call(xAxis_VF); // Create an axis component with d3.axisBottom
var gBX_VF = bottomPanel_VF.append("g")
    .attr("id", "xBrush_VF")
    .attr("class", "brush")
    .call(brushX_VF);
    
var leftPanel_VF = svg_VF.append("g")
    .attr("id", "lPanel_VF")
    .attr("class", "panel")
    .attr("transform", "translate("+margin.left+","+0+")");

var yAxis_VF = d3.axisLeft(yScale_VF);
var gY_VF = leftPanel_VF.append("g")
    .attr("id", "yAxis_VF")
    .attr("class", "axis")
    .call(yAxis_VF); // Create an axis component with d3.axisLeft
var gBY_VF = leftPanel_VF.append("g")
    .attr("id", "yBrush_VF")
    .attr("class", "brush")
    .call(brushY_VF);
    
    
// trans_dir example:
// {
//   0: {var_1: {down: {in: true, out: false}, up: {in: true, out: true}}, 
//       var_2: {down: {in: false, out: false}, up: {in: false, out: true}},
//       ...},
//   1: {...},
//   ...
// }

// trans example = {
//   0:[0,1],
//   1:[0,3],
//   2:[3],
//   3:[3]
// };

var xScale = d3.scaleLinear()
  .domain([d3.min(thrs[xDim],parseFloat),
           d3.max(thrs[xDim],parseFloat)])
  .range([margin.left, width - margin.right]);

var yScale = d3.scaleLinear()
  .domain([d3.min(thrs[yDim],parseFloat),
           d3.max(thrs[yDim],parseFloat)])
  .range([height - margin.bottom, margin.top]);

var brushX = d3.brushX()
    .extent([[margin.left, 0], [width-margin.right, margin.bottom]])
    .on("end", brushedX),
    
    brushY = d3.brushY()
    .extent([[-margin.left, margin.top], [0, height-margin.bottom]])
    .on("end", brushedY);

var zoom = d3.zoom()
          //.scaleExtent([1, Infinity])
          //.translateExtent([[0,0],[width,height]])
          .on("zoom", zoomed);
var svg = d3.select("body").append("svg")
    .attr("width", width)
    .attr("height", height);

var container = svg.append("g")
        .attr("id","cont")
        //.attr("transform", "translate("+(margin.left)+","+(margin.top)+")")
        .call(zoom);

var xLabel = svg.append("text")
    .attr("id", "xlabel")
    .attr("class", "label")
    .attr("x", width*0.5)
    .attr("y", height-10)
    .attr("stroke", "black")
    .text(function() { return xDim; });
var yLabel = svg.append("text")
    .attr("id", "ylabel")
    .attr("class", "label")
    .attr("transform", "rotate(-90)")
    .attr("x", -width*0.5)
    .attr("y", 15)
    .attr("stroke", "black")
    .text(function() { return yDim; });

var bottomPanel = svg.append("g")
    .attr("id", "bPanel")
    .attr("class", "panel")
    .attr("transform", "translate("+(0)+","+(height-margin.bottom)+")");
    
var xAxis = d3.axisBottom(xScale);
var gX = bottomPanel.append("g")
    .attr("id", "xAxis")
    .attr("class", "axis")
    .call(xAxis); // Create an axis component with d3.axisBottom
var gBX = bottomPanel.append("g")
    .attr("id", "xBrush")
    .attr("class", "brush")
    .call(brushX);
    
var leftPanel = svg.append("g")
    .attr("id", "lPanel")
    .attr("class", "panel")
    .attr("transform", "translate("+margin.left+","+0+")");

var yAxis = d3.axisLeft(yScale);
var gY = leftPanel.append("g")
    .attr("id", "yAxis")
    .attr("class", "axis")
    .call(yAxis); // Create an axis component with d3.axisLeft
var gBY = leftPanel.append("g")
    .attr("id", "xBrush")
    .attr("class", "brush")
    .call(brushY);

compute_tss();
transform_tss();
draw();
fill_info_panel_outside();

generateGrid_VF();
draw_VF();
    
// ################# definitions of functions #################
    
function generateGrid_VF() {
  vectors_VF = [];
  
  var xmin = zoomObject_VF.rescaleX(xScale_VF).domain()[0],
      xmax = zoomObject_VF.rescaleX(xScale_VF).domain()[1],
      ymin = zoomObject_VF.rescaleY(yScale_VF).domain()[0],
      ymax = zoomObject_VF.rescaleY(yScale_VF).domain()[1],
      xp = d3.range(xmin,xmax,(xmax-xmin)/gridSize_VF),
      yp = d3.range(ymin,ymax,(ymax-ymin)/gridSize_VF);
  xp[xp.length] = xmax;
  yp[yp.length] = ymax;
  
  for (var i = 0; i < yp.length; i++) {
    for (var j = 0; j < xp.length; j++) {
      
      var vars = {};
      // fill variables with current values
      for(var v in window.bio.vars) {
        val = window.bio.vars[v];
        // for vars on X and Y it is value of current vector origin
        if(val == xDim) vars[val] = xp[j];
        else if(val == yDim) vars[val] = yp[i];
        // for the rest of variables (besides X and Y) according to slider for variables
        else vars[val] = Number(d3.select("#slider_"+val+"_VF").property("value"));
      }
      var diffs = {};
      for (const [key, eq] of Object.entries(window.bio.eqs)) {
        diffs[key] = Number(eq(vars, params));
      }
      var direction = (color_style_VF == "both" ? diffs[xDim]+diffs[yDim] : (color_style_VF == "vertical" ? diffs[yDim] : (color_style_VF == "horizontal" ? diffs[xDim] : 0)));
      vectors_VF.push({
        id: i*xp.length+j,
        x0: zoomObject_VF.rescaleX(xScale_VF)(xp[j]),
        y0: zoomObject_VF.rescaleY(yScale_VF)(yp[i]),
        x1: zoomObject_VF.rescaleX(xScale_VF)(xp[j]+diffs[xDim]*dt_VF),
        y1: zoomObject_VF.rescaleY(yScale_VF)(yp[i]+diffs[yDim]*dt_VF),
        head:  (direction > Number(color_thr_VF) ? "url(#positiveArrow)" : (direction < -Number(color_thr_VF) ? "url(#negativeArrow)" : "url(#neutralArrow)")),
        color: (direction > Number(color_thr_VF) ? positive_col : (direction < -Number(color_thr_VF) ? negative_col : neutral_col)),
      });
    }
  }
}
   
function update_axes_VF() {
  // Update axes labels according to selected diemnsions
  d3.select('#xLabel_VF').text(xDim);
  d3.select('#ylabel_VF').text(yDim);
  // Update scales according to selected diemnsions
  xScale_VF.domain([d3.min(thrs[xDim],parseFloat),
                 d3.max(thrs[xDim],parseFloat)])

  yScale_VF.domain([d3.min(thrs[yDim],parseFloat),
                 d3.max(thrs[yDim],parseFloat)])
  // reset brushes
  gBX_VF.call(brushX_VF.move, null);
  gBY_VF.call(brushY_VF.move, null);
}
function resettedReach_VF() {
  reach_start_VF = null; 
  reach_end_VF = null; 
  trajectory_VF_length = 1000; 
  d3.select("#trajectory_VF").remove();
}
function resettedZoom_VF() {
  update_axes_VF()
  container_VF.transition()
      .duration(500)
      .call(zoom_VF.transform, d3.zoomIdentity);
}
function zoomed_VF() {
  if(d3.event.transform) zoomObject_VF = d3.event.transform;
 
  generateGrid_VF();
  draw_VF();
  if(reach_start_VF !== null) reach_VF(null);
  
  gX_VF.call(xAxis_VF.scale(zoomObject_VF.rescaleX(xScale_VF)));
  gY_VF.call(yAxis_VF.scale(zoomObject_VF.rescaleY(yScale_VF)));
  // reset brushes
  gBX_VF.call(brushX_VF.move, null);
  gBY_VF.call(brushY_VF.move, null);
}
function brushedX_VF() {
  if (!d3.event.sourceEvent) return; // Only transition after input.
  if (!d3.event.selection) return; // Ignore empty selections.
  var sel = d3.event.selection;
  var domain = sel.map(xAxis_VF.scale().invert);
  // TODO: set up brush.move for scale over some threshold (similar to zoom_VF.scaleExtent([1, 100000]) ) to force it to resize along that threshold
  //console.log((d3.max(thrs[xDim],parseFloat)-d3.min(thrs[xDim],parseFloat))/(domain[1]-domain[0]));
  //if((d3.max(thrs[xDim],parseFloat)-d3.min(thrs[xDim],parseFloat))/(domain[1]-domain[0]) > 100000) return;
    
  scale = xScale_VF.copy().domain(domain);
  range = scale.range().map(x => zoomObject_VF.applyX(x));
  domain = range.map(scale.invert);
  xScale_VF.domain(domain);
  
  zoomed_VF()
}
function brushedY_VF() {
  if (!d3.event.sourceEvent) return; // Only transition after input.
  if (!d3.event.selection) return; // Ignore empty selections.
  var sel = d3.event.selection;
  var domain = sel.map(yAxis_VF.scale().invert);
  
  scale = yScale_VF.copy().domain(domain.reverse());
  range = scale.range().map(y => zoomObject_VF.applyY(y));
  domain = range.map(scale.invert);
  yScale_VF.domain(domain);
  
  zoomed_VF()
}
function handleMouseOver_VF(d, i) {
  var div = document.getElementById("infoPanel_VF");
  var mouse = d3.mouse(this),
      vars = {};
  // fill variables with values of mouse position and sliders
  for(var v = 0; v < window.bio.vars.length; v++) {
    var key = window.bio.vars[v];
    if(key == xDim)       vars[key] = zoomObject_VF.rescaleX(xScale_VF).invert(mouse[0]);
    else if(key == yDim)  vars[key] = zoomObject_VF.rescaleY(yScale_VF).invert(mouse[1]);
    else                  vars[key] = Number(d3.select("#slider_"+key+"_VF").property("value"));
  }
  // compute derivatives with current values of parameters and variables
  var diffs = {};
  for (const [key, eq] of Object.entries(window.bio.eqs)) {
    diffs[key] = Number(eq(vars, params));
  }
  
  var content = "Route start: "+(reach_start_VF !== null ? ""+parsing_to_string(reach_start_VF)+"" : "none");
  content +=  "\nRoute end:   "+(reach_end_VF !== null ? ""+parsing_to_string(reach_end_VF)+"" : "none");
  for(var v = 0; v < window.bio.vars.length; v++) {
    var key = window.bio.vars[v];
    content += "\n"+key+": "+(vars[key].toFixed(3))+"\td["+key+"]: "+(diffs[key].toFixed(3));
  }
  div.value = content;
}
function handleMouseOut_VF(d, i) {
  var div = document.getElementById("infoPanel_VF");
  var content = "Route start: "+(reach_start_VF !== null ? ""+parsing_to_string(reach_start_VF)+"" : "none");
  content +=  "\nRoute end:   "+(reach_end_VF !== null ? ""+parsing_to_string(reach_end_VF)+"" : "none");
  for(var v = 0; v < window.bio.vars.length; v++) {
    var key = window.bio.vars[v];
    var value = key == xDim ? zoomObject_VF.rescaleX(xScale_VF).domain() : (key == yDim ? zoomObject_VF.rescaleY(yScale_VF).domain() : Number(d3.select("#slider_"+key+"_VF").property("value")) );
    content += "\n"+key+": "+(key == xDim || key == yDim ? ("["+(+value[0].toFixed(3))+", "+(+value[1].toFixed(3))+"]") : (+value.toFixed(3)));
  }
  div.value = content;
}
function elongate_VF() {
  d3.select("#trajectory_VF").remove();
  var vars = Object.assign({}, reach_end_VF);
  
  var length = 500
  for(var tp = 0; tp < length; tp++) {
    // compute derivatives with current values of parameters and variables
    var diffs = {}
    for (const [key, eq] of Object.entries(window.bio.eqs)) 
      diffs[key] = Number(eq(vars, params))
    var tempvars = Object.assign({}, vars);
    for (const [key, val] of Object.entries(diffs))
      tempvars[key] += val*traj_dt_VF
    if(Object.values(tempvars).includes(Infinity) || Object.values(tempvars).includes(-Infinity) || Object.values(tempvars).includes(NaN)) {
      console.log("Derivation went to infinite numbers!",tempvars)
      break
    } else {
      vars = Object.assign({}, tempvars)
      trajectory_VF += "L"+zoomObject_VF.rescaleX(xScale_VF)(vars[xDim])+","+zoomObject_VF.rescaleY(yScale_VF)(vars[yDim])+" ";
    }
  }
  reach_end_VF = Object.assign({}, vars);
  trajectory_VF_length += length;
  container_VF.append("path")
      .attr("id", "trajectory_VF")
      .attr("class", "vector_VF")
      .attr("stroke", reachColor_VF)
      .attr("stroke-width", selfloopWidth_VF)
      .attr("marker-end", "url(#reachArrow)")
      .attr("d", trajectory_VF);
  d3.select("#zoomField_VF").moveUp();
}
// counts trajectory in VF from selected origin point
function reach_VF(event) {
  if(event !== null) {
      // this part is for clean new trajectory after mouse-click event
      reach_start_VF = {};
      reach_end_VF = null;
      trajectory_VF_length = 1000;
      d3.select("#trajectory_VF").remove();
      // fill variables with values of mouse position and sliders
      for(var v = 0; v < window.bio.vars.length; v++) {
        var key = window.bio.vars[v];
        if(key == xDim)       reach_start_VF[key] = zoomObject_VF.rescaleX(xScale_VF).invert(event[0]);
        else if(key == yDim)  reach_start_VF[key] = zoomObject_VF.rescaleY(yScale_VF).invert(event[1]);
        else                  reach_start_VF[key] = Number(d3.select("#slider_"+key+"_VF").property("value"));
      }
  }
  var vars = Object.assign({}, reach_start_VF)
  trajectory_VF = "M"+zoomObject_VF.rescaleX(xScale_VF)(vars[xDim])+","+zoomObject_VF.rescaleY(yScale_VF)(vars[yDim])+" ";
  
  var length = trajectory_VF_length;
  for(var tp = 0; tp < length; tp++) {
    // compute derivatives with current values of parameters and variables
    var diffs = {}
    for (const [key, eq] of Object.entries(window.bio.eqs))
      diffs[key] = Number(eq(vars, params))
    var tempvars = Object.assign({}, vars);
    for (const [key, val] of Object.entries(diffs))
      tempvars[key] += val*traj_dt_VF
    if(Object.values(tempvars).includes(Infinity) || Object.values(tempvars).includes(-Infinity) || Object.values(tempvars).includes(NaN)) {
      console.log("Derivation went to infinite numbers!",tempvars)
      console.log(vars)
      break
    } else {
      vars = Object.assign({}, tempvars)
      trajectory_VF += "L"+zoomObject_VF.rescaleX(xScale_VF)(vars[xDim])+","+zoomObject_VF.rescaleY(yScale_VF)(vars[yDim])+" ";
    }
  }
  reach_end_VF = Object.assign({}, vars);
  container_VF.append("path")
      .attr("id", "trajectory_VF")
      .attr("class", "vector_VF")
      .attr("stroke", reachColor_VF)
      .attr("stroke-width", selfloopWidth_VF)
      .attr("marker-end", "url(#reachArrow)")
      .attr("d", trajectory_VF);
  d3.select("#zoomField_VF").moveUp();
}
// function for in-field mouse-click event (counts trajectory in VF)
function handleMouseClick_VF(d, i) {
  reach_VF(d3.mouse(this));
}

function draw_VF() {
  container_VF.selectAll(".vector_VF").remove();
  container_VF.select("#zoomField_VF").remove();
  
  container_VF.selectAll(".vector_VF")
    .data(vectors_VF)
    .enter()
    .append("path")
    .attr("id", d => d.id)
    .attr("class", "vector_VF")
    .attr("marker-end", d => d.head)
    .attr("stroke", d => d.color)
    .attr("stroke-width", transWidth_VF)
    .attr("d", d => "M"+(d.x0)+" "+(d.y0)+" L"+(d.x1)+" "+(d.y1)+" ");
      
    
  container_VF.append("rect")
    .attr("id", "zoomField_VF")
    .attr("x", margin.left)
    .attr("y", margin.top)
    .attr("width", width-margin.right-margin.left)
    .attr("height", height-margin.bottom-margin.top)
    .attr("fill", "none")
    .on("click", handleMouseClick_VF)
    .on("mousemove", handleMouseOver_VF)
    .on("mouseout", handleMouseOut_VF);
}

//#########

// returns one layer of TSS = array of N arrays (N = dimensions/variables count) where each array contains concerned thresholds (for X and Y all, for the rest just two)
function generateProjection(thrs, x, y) {
  var multiarray = [];
  window.bio.vars.forEach(key => {
    var arr = [];
    var val = thrs[key].map(Number);
    if(key == x || key == y) arr = val;       // return all thresholds (for variable on X or Y)
    else {
      // return nearest lower and upper threshold according to value of slider (for other variables)
      aVal = Number(d3.select("#slider_"+key).property("value"));
      if(aVal == d3.max(val)) arr = val.slice(-2);
      else arr = [d3.max(val.filter(x => x <= aVal)), d3.min(val.filter(x => x > aVal))];
    }
    multiarray.push(arr);
  });
  return multiarray;
}
    
// computes all unique combinations of N arrays inside one array into new array of M arrays of length N where each item is from different initial array
// input and output is just array of arrays
function getCombitations(arrays, combine = [], finalList = []) {
    if (!arrays.length) {
        finalList.push(combine);
    } else {
        arrays[0].forEach(now => {
            let nextArrs = arrays.slice(1);
            let copy = combine.slice();
            copy.push(now);
            getCombitations(nextArrs, copy, finalList);
        });
    }
    return finalList;
}
// adds transition to 'trans' structure from state with id 'from' to state with id 'to'
function check_and_add_trans(from, to) {
  if(trans.hasOwnProperty(Number(from)))  { 
    if(!trans[Number(from)].includes(Number(to))) trans[Number(from)] = trans[Number(from)].concat([Number(to)])
  } else trans[Number(from)] = [Number(to)];
}

// computes all possible transitions for particular vertex (vars and params contain one value for each item)
function compute_trans(vars, params, inds) {
  //console.log("current vertex ids: "+inds);
  var marr = [];
  for(const [key, vid] of Object.entries(inds)) {
    marr.push(vid == 0 ? [vid] : (vid == (thrs[key].length-1) ? [vid-1] : [vid, vid-1]));
  }
  // computes derivatives for all equations in current vertex with current parameters
  var diffs = {};
  for(const [key, eq] of Object.entries(window.bio.eqs)) {
    diffs[key] = eq(vars, params);
  }
  // creates all meaningful state ids in neighborhood of current vertex
  var combs = getCombitations(marr);
  for(var c = 0; c < combs.length; c++) {
    //console.log("source for state id: "+combs[c]);
    var comb = {};
    var offset_all = 1;
    var offset = {};
    var state_id = 0;
    for(const vid in window.bio.vars) {
      const key = window.bio.vars[vid];
      comb[key] = combs[c][vid];
      offset[key] = offset_all;
      state_id += comb[key] * offset[key];
      offset_all *= thrs[key].length - 1;
    }
    // reistration of state in trans_dir structure
    if(!trans_dir.hasOwnProperty(state_id)) trans_dir[state_id] = {};
    
    for(const [key, diff] of Object.entries(diffs)) {
      // registartion of state's directions in current dimension (all to false at start)
      if(!trans_dir[state_id].hasOwnProperty(key)) trans_dir[state_id][key] = {down: {in: false, out: false}, up: {in: false, out: false}};
      
      // current state is upstream to vertex
      if(comb[key] == inds[key]) {
        // negative derivative in this dimension
        if(diff < 0)  {
          trans_dir[state_id][key]['down']['out'] = true; // adds necessary direction independently of transitions
          if(inds[key] > 0) {   // checks if current state is not on lower border
            var neigh_id = state_id-offset[key];  // ID of state at the end of transition from current state
            check_and_add_trans(state_id, neigh_id);
          }
        // positive derivative in this dimension
        } else if(diff > 0) {
          trans_dir[state_id][key]['down']['in'] = true; // adds necessary direction independently of transitions
          if(inds[key] > 0) {   // checks if current state is not on lower border
            var neigh_id = state_id-offset[key];  // ID of state at the beginning of transition to current state
            check_and_add_trans(neigh_id, state_id);
          }
        }
      // current state is downstream to vertex
      } else if(comb[key] < inds[key]) {
        // negative derivative in this dimension
        if(diff < 0)  {
          trans_dir[state_id][key]['up']['in'] = true; // adds necessary direction independently of transitions
          if(inds[key] < thrs[key].length-1) {   // checks if current state is not on upper border
            var neigh_id = state_id+offset[key];  // ID of state at the end of transition from current state
            check_and_add_trans(neigh_id, state_id);
          }
        // positive derivative in this dimension
        } else if(diff > 0) {
          trans_dir[state_id][key]['up']['out'] = true; // adds necessary direction independently of transitions
          if(inds[key] < thrs[key].length-1) {   // checks if current state is not on upper border
            var neigh_id = state_id+offset[key];  // ID of state at the beginning of transition to current state
            check_and_add_trans(state_id, neigh_id);
          }
        }
      // this shouldn't occur
      } else {
        console.log("ERROR: nonsense - it occured greater threshold in dim "+key+" then current vertex (comb[key] > inds[key])")
      }
    }
  }
}
// coumputes all transitions and stores them into dictionary 'trans' (all numbers are indices of states) 
function compute_tss() {
  trans = {};
  trans_dir = {};
  
  var marr = [];
  window.bio.vars.forEach(key => {
    marr.push(thrs[key].map(Number));
  });
  // computes all vertices of state space
  var combinations = getCombitations(marr);
  // iterates over all vertices to compute transitions
  for(var c = 0; c < combinations.length; c++) {
    var vert_val = {},
        vert_ids = {};
    // fill the variables current values according to this vertex
    for(var v in window.bio.vars) {
      key = window.bio.vars[v];
      vert_val[key] = combinations[c][v];
      // it is important to store indices for all dimensions of current vertex
      vert_ids[key] = thrs[key].findIndex(x => Number(x) == vert_val[key]);
    }
    compute_trans(vert_val, params, vert_ids);
  }
  // part for adding of self-loops
  for(const [sid, dims] of Object.entries(trans_dir)) {
    var selfloop = true;
    for(const [dim, dirs] of Object.entries(dims)) {
      selfloop = selfloop && !( (dirs.up.in && dirs.down.out && !dirs.up.out && !dirs.down.in) || 
                                (dirs.up.out && dirs.down.in && !dirs.up.in && !dirs.down.out) )
    }
    if(selfloop) {
      check_and_add_trans(sid,sid);
    }
  }
}
// transforms list of states and transitions among states into svg component attributes
function transform_tss() {
  statedata = {};
  transdata = [];
  multiarr = generateProjection(thrs, xDim, yDim)
  
  var states_start = getCombitations(multiarr.map(x => x.filter(v => v < d3.max(x))))
  var states_end = getCombitations(multiarr.map(x => x.filter(v => v > d3.min(x))))
  var xDim_id = window.bio.vars.findIndex(x => x == xDim);
  var yDim_id = window.bio.vars.findIndex(x => x == yDim);
  var accepted_state_ids = [];

  for(var s = 0; s < states_start.length; s++) {
    var offset = 1;
    var state_id = 0;
    for(const vid in window.bio.vars) {
      const key = window.bio.vars[vid];
      idx = thrs[key].findIndex(x => Number(x) == states_start[s][vid])
      state_id += idx * offset;
      offset *= (thrs[key].length - 1);
    }
    accepted_state_ids.push(state_id);
    statedata[state_id] = {
        x:  states_start[s][xDim_id],
        y:  states_end[s][yDim_id],
        x1: states_end[s][xDim_id],
        y1: states_start[s][yDim_id],
        id: "s"+state_id};
  }

  accepted_state_ids.filter(x => trans[x] !== undefined).forEach(sid => {
    trans[sid].filter(x => accepted_state_ids.includes(x)).forEach(nid => {
      var begin = statedata[sid];
      var end = statedata[nid];
      
      transdata.push({
        x0: (begin.x+begin.x1)/2,
        y0: (begin.y+begin.y1)/2,
        x1: (begin.x == end.x ? 
             (begin.x+begin.x1)/2 : 
             (begin.x < end.x ? begin.x1 : begin.x)),
        y1: (begin.y == end.y ? 
             (begin.y+begin.y1)/2 : 
        // NOTE: the end point of transition in Y axis, the condition must be the opposite because current values are in model scale (domain, not range) 
        // and so they will be rescaled upside down for drawing
             (begin.y > end.y ? begin.y1 : begin.y)),
        // NOTE: points [x2,y2] and [x3,y3] (arrow head) are set in frame scale (range, not domain) because they need to remain constant during zooming
        x2: (begin.x == end.x ? 
             -0.5*arrowlen :
             (begin.x < end.x ? -arrowlen : arrowlen)),
        y2: (begin.y == end.y ? 
             -0.5*arrowlen :
             (begin.y > end.y ? -arrowlen : arrowlen)),
        x3: (begin.x == end.x ? arrowlen : 0),
        y3: (begin.y == end.y ? arrowlen : 0),
        id: "t"+sid+"-"+nid,
        color:  (begin == end || color_style == "none" ? neutral_col : 
                  (color_style == "both" ? (begin.x < end.x || begin.y < end.y && color_style ? positive_col : negative_col) :
                    ((begin.x < end.x && color_style == "horizontal") || (begin.y < end.y && color_style == "vertical") ? positive_col : 
                      ((begin.x > end.x && color_style == "horizontal") || (begin.y > end.y && color_style == "vertical") ? negative_col : neutral_col)))),
        class: (begin == end ? "loop" : "transition")});
    });
  })
  //console.log(transdata);
}

function update_axes() {
  // Update axes labels according to selected diemnsions
  d3.select('#xlabel').text(xDim);
  d3.select('#ylabel').text(yDim);
  // Update scales according to selected diemnsions
  xScale.domain([d3.min(thrs[xDim],parseFloat),
                 d3.max(thrs[xDim],parseFloat)])

  yScale.domain([d3.min(thrs[yDim],parseFloat),
                 d3.max(thrs[yDim],parseFloat)])
  // Update an axis component according to selected dimensions
  xAxis = d3.axisBottom(xScale);
  gX.call(xAxis);
  yAxis = d3.axisLeft(yScale);
  gY.call(yAxis);
  // reset brushes
  gBX.call(brushX.move, null);
  gBY.call(brushY.move, null);
}
function resettedReach() {
  reach_start=null; 
  d3.selectAll(".states").attr("fill", noColor);
  fill_info_panel_outside();
}
function resettedZoom() {
  update_axes()
  container.transition()
      .duration(500)
      .call(zoom.transform, d3.zoomIdentity);
}
function zoomed() {
  if(d3.event.transform) zoomObject = d3.event.transform;
  x = zoomObject.rescaleX(xScale);
  y = zoomObject.rescaleY(yScale);
  
  d3.selectAll(".transition")
    .attr("d", d => "M"+x(d.x0)+" "+y(d.y0)+" L"+x(d.x1)+" "+y(d.y1)+"\
                    l"+(d.x2)+" "+(d.y2)+" l"+(d.x3)+" "+(d.y3)+" \
                    L"+x(d.x1)+" "+y(d.y1)+" Z"); // NOTE: d.x2, d.y2, d.x3, d.y3 are in different scale
  
  d3.selectAll(".loop")
    .attr("cx", d => x(d.x0))
    .attr("cy", d => y(d.y0))
  
  d3.selectAll(".states")
    .attr("x", d => x(d.x))
    .attr("y", d => y(d.y))
    .attr("width", d => x(d.x1)-x(d.x))
    .attr("height", d => y(d.y1)-y(d.y))
  
  gX.call(xAxis.scale(x));
  gY.call(yAxis.scale(y));
  // reset brushes
  gBX.call(brushX.move, null);
  gBY.call(brushY.move, null);
}
function brushedX() {
  if (!d3.event.sourceEvent) return; // Only transition after input.
  if (!d3.event.selection) return; // Ignore empty selections.
  var sel = d3.event.selection;
  var domain = sel.map(xAxis.scale().invert);
  // TODO: set up brush.move for scale over some threshold (similar to zoom.scaleExtent([1, 100000]) ) to force it to resize along that threshold
  // TODO: implement own control over zoom extent because with embeded functions either it's not possible to move or unzoome after brush or
  //       it's possible to zoom out into a point
    
  scale = xScale.copy().domain(domain);
  range = scale.range().map(x => zoomObject.applyX(x));
  domain = range.map(scale.invert);
  xScale.domain(domain);
  
  zoomed();
}
function brushedY() {
  if (!d3.event.sourceEvent) return; // Only transition after input.
  if (!d3.event.selection) return; // Ignore empty selections.
  var sel = d3.event.selection;
  var domain = sel.map(yAxis.scale().invert);
  
  scale = yScale.copy().domain(domain.reverse());
  range = scale.range().map(y => zoomObject.applyY(y));
  domain = range.map(scale.invert);
  yScale.domain(domain);
  
  zoomed();
}
function fill_info_panel(d) {
  var div = document.getElementById("infoPanel");
  var content =  "reach from: "+(reach_start == null ? "none" : reach_start);
      content += "\nstate: "+d.id.slice(1)+"";
  for(var v = 0; v < window.bio.vars.length; v++) {
    var key = window.bio.vars[v];
    if(xDim == key)
      // (+some_number) is a trick how to get rid of trailling zeroes
      content += "\n"+xDim+": ["+(+parseFloat(d.x).toFixed(3))+", "\
                                +(+parseFloat(d.x1).toFixed(3))+"]";
    else if(yDim == key)
      content += "\n"+yDim+": ["+(+parseFloat(d.y1).toFixed(3))+", "\
                                +(+parseFloat(d.y).toFixed(3))+"]";
    else
      content += "\n"+key+": ["+d3.min(multiarr[v].map(Number))+", "+d3.max(multiarr[v].map(Number))+"]";
  }
  div.value = content;
}
function handleMouseOver(d, i) {
  d3.select(this).attr("stroke-width", hoverStrokeWidth);
  d3.select(this).attr("pointed", true);
  
  fill_info_panel(d);
}
function fill_info_panel_outside() {
  var div = document.getElementById("infoPanel");
  var content =  "reach from: "+(reach_start == null ? "none" : reach_start);
      content += "\nstate: none";
  for(var v = 0; v < window.bio.vars.length; v++) {
    var key = window.bio.vars[v];
    if(xDim == key)
      // (+some_number) is a trick how to get rid of trailling zeroes
      content += "\n"+xDim+": ["+(+xScale.domain()[0].toFixed(3))+", "\
                                +(+xScale.domain()[1].toFixed(3))+"]";
    else if(yDim == key)
      content += "\n"+yDim+": ["+(+yScale.domain()[0].toFixed(3))+", "\
                                +(+yScale.domain()[1].toFixed(3))+"]";
    else
      content += "\n"+key+": ["+d3.min(multiarr[v].map(Number))+", "+d3.max(multiarr[v].map(Number))+"]";
  }
  div.value = content;
}
function handleMouseOut(d, i) {
  d3.select(this).attr("stroke-width", normalStrokeWidth);
  d3.select(this).attr("pointed", false);
  
  fill_info_panel_outside();
}
// counts rachability in TSS from state with ID index, results in array of reachable state indices
function reach(index) {
  var out = new Set([index]),
      cElem = new Set([index]);
  do {
    cElem.forEach(elem => {if(trans.hasOwnProperty(elem)) trans[elem].forEach(el => {cElem.add(el)})});
    var cSize = out.size;
    cElem = cElem.difference(out)
    cElem.forEach(el => {out.add(el)})
  } while (cSize != out.size);
  return [...out];
}
// function for on-state mouse-click event (counts reachability in TSS)
function handleMouseClick(d, i) {
  reach_start = (d !== null ? Number(d.id.slice(1)) : Number(i));
  var reachable = reach(reach_start);
  d3.selectAll(".states").attr("fill", noColor);
  d3.selectAll(".states")
    .filter(x => {return reachable.includes(Number(x.id.slice(1))) })
    .attr("fill", reachColor_TS);
  if(d !== null) fill_info_panel(d);
}

function draw() {
  
  d3.selectAll(".states").remove();     // because of the automatic redrawing of TSS in response slider etc.
  d3.selectAll(".transition").remove(); // because of the automatic redrawing of TSS in response slider etc.
  d3.selectAll(".loop").remove();       // because of the automatic redrawing of TSS in response slider etc.

  container.selectAll(".transition")
    .data(transdata.filter(d => d.class == "transition"))
    .enter()
    .append("path")
    .attr("id", d => d.id)
    .attr("class", "transition")
    .attr("stroke", d => d.color)
    .attr("stroke-width", transWidth)
    .attr("d", d => "M"+xScale(d.x0)+" "+yScale(d.y0)+" L"+xScale(d.x1)+" "+yScale(d.y1)+"\
                    l"+(d.x2)+" "+(d.y2)+" l"+(d.x3)+" "+(d.y3)+" \
                    L"+xScale(d.x1)+" "+yScale(d.y1)+" Z"); // NOTE: d.x2, d.y2, d.x3, d.y3 are in different scale
                    
  container.selectAll(".loop")
    .data(transdata.filter(d => d.class == "loop"))
    .enter()
    .append("circle")
    .attr("id", d => d.id)
    .attr("class", "loop")
    .attr("cx", d => xScale(d.x0))
    .attr("cy", d => yScale(d.y0))
    .attr("r", selfloopWidth)
    .attr("stroke", d => d.color);
  
  container.selectAll(".states")
    .data(Object.values(statedata))
    .enter()
    .append("rect")
    .attr("class", "states")
    .attr("id", d => d.id)
    .attr("x", d => xScale(d.x))
    .attr("y", d => yScale(d.y))
    .attr("width", d => xScale(d.x1)-xScale(d.x))
    .attr("height", d => yScale(d.y1)-yScale(d.y))
    .attr("fill", noColor)
    .attr("stroke", "black")
    .attr("stroke-width", normalStrokeWidth)
    .attr("pointed", false)
    .on("click", handleMouseClick)
    .on("mouseover", handleMouseOver)
    .on("mouseout", handleMouseOut);
}


    </script>
  </body>

</html>
