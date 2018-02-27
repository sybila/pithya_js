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
    cmd = "echo '{}' | {} > {}".format(data_text,approx_path,output_data)
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
    <title>VF - Vector field</title>
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
          if(s >= a[0] && s <= b[0]) return(a[1]+(s-a[0])/(b[0]-a[0])*(b[1]-a[1]))
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

    <style>
      body {
        background-color: white;
        margin: 0;
        font-family: sans-serif;
        font-size: 18px;
      }
      #cont {
        pointer-events: all;
      }
      #zoomObject {
      }
      .vector { 
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
      #resetZoomBtn {
        position: absolute;
        top: 10px;
      }
      #resetReachBtn {
        position: absolute;
        top: 40px;
      }
      #elongateReachBtn {
        position: absolute;
        top: 40px;
        left: 80px;
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
      .slidecontainer {
        position: absolute;
        top: 200px;
      }
      #inputs_div {
        position: absolute;
        top: 450px;
      }
    </style>
  </head>
    
  <body>
    <div class="widget_panel">
      <button id="resetZoomBtn">Unzoom</button>
      <button id="resetReachBtn">Deselect</button>
      <button id="elongateReachBtn">Elongate</button>
      <textarea id="infoPanel" rows="${len(vars)+2}" cols="35" wrap="off" disabled></textarea>
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
        <div class="slidecontainer">
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
      <div id="inputs_div">
        <hr>
        arrows count: <span id="text_gridSize"></span><br>
        <input type="range" min=10 max=100 value=25 step=1 class="slider" id="input_gridSize"><br>
        derivative scale: <span id="text_dt"></span><br>
        <input type="range" min=0.01 max=1 value=1 step=0.01 class="slider" id="input_dt"><br>
        colouring threshold: <span id="text_color_thr"></span><br>
        <input type="range" min=0 max=0.1 value=0.05 step=0.01 class="slider" id="input_color_thr"><br>
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
    dt = Number(d3.select("#input_dt").property("value")),
    traj_dt = 0.1,
    // TODO: following should be connected to particular slider (or some input element) as it's in Pithya
    color_style = d3.select("#input_color_style").property("value"),
    color_thr = Number(d3.select("#input_color_thr").property("value")),
    gridSize = Number(d3.select("#input_gridSize").property("value"));

// initial values according to the sliders setting
window.bio.params.map(x => params[x[0]] = x[1]);
    
// iteratively adds event listener for varaible sliders (according to index)
% if len(vars) > 2:
  % for val in vars:
      (function(i) {
          d3.select("#text_"+i).html(d3.select("#slider_"+i).property("value"));
          d3.select("#slider_"+i).on("input", function() {
              d3.select("#text_"+i).html(this.value);
              zoomed();
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
              zoomed();
          })
      })(${val});
  % endfor
% endif

// sets text value for slider of arrows_count and adds event listener for change of slider
d3.select("#text_gridSize").html(d3.select("#input_gridSize").property("value"));
d3.select('#input_gridSize').on("input", function() {
  d3.select("#text_gridSize").html(this.value);
  gridSize = Number(this.value);
  zoomed();
});

// sets text value for slider of derivative_scale and adds event listener for change of slider
d3.select("#text_dt").html(d3.select("#input_dt").property("value"));
d3.select('#input_dt').on("input", function() {
  d3.select("#text_dt").html(this.value);
  dt = Number(this.value);
  zoomed();
});

// sets text value for slider of colouring_threshold and adds event listener for change of slider
d3.select("#text_color_thr").html(d3.select("#input_color_thr").property("value"));
d3.select('#input_color_thr').on("input", function() {
  d3.select("#text_color_thr").html(this.value);
  color_thr = Number(this.value);
  zoomed();
});

// adds event listener for change of colouring_orientation
d3.select('#input_color_style').on("input", function() {
  color_style = this.value;
  zoomed();
});

// event listener for change of selectected dimension for X axis
d3.select("#x_axis").on("change", function() {
  var other = d3.select("#y_axis").property("value");
  if(this.value == other) {
    d3.select("#y_axis").property('value',xDim);
    yDim = xDim;
  } else {
    d3.select("#slider_"+xDim+"_wrapper").attr("hidden",null);
  }
  xDim = this.value;
  d3.select("#slider_"+this.value+"_wrapper").attr("hidden","hidden");
  resettedZoom();
});

// event listener for change of selectected dimension for Y axis
d3.select("#y_axis").on("change", function() {
  var other = d3.select("#x_axis").property("value");
  if(this.value == other) {
    d3.select("#x_axis").property('value',yDim);
    xDim = yDim;
  } else {
    d3.select("#slider_"+yDim+"_wrapper").attr("hidden",null);
  }
  yDim = this.value;
  d3.select("#slider_"+this.value+"_wrapper").attr("hidden","hidden");
  resettedZoom();
});

// event listeners for buttons
d3.select('#resetReachBtn')
    .on("click", resettedReach);
    
d3.select('#elongateReachBtn')
    .on("click", elongate);

d3.select('#resetZoomBtn')
    .on("click", resettedZoom);


//###################################################  

var width = 550,
    height = 550,
    margin = { top: 10, right: 10, bottom: 50, left: 50 },
    arrowlen = 3,
    color = "transparent",
    reachColor = "royalblue",
    neutral_col = "black",
    positive_col = "darkgreen",
    negative_col = "red",
    reach_start = null,
    reach_end = null,
    trajectory = "",
    trajectory_length = 1000,
    normalStrokeWidth = 1,
    hoverStrokeWidth = 4,
    transWidth = 2,
    selfloopWidth = 4,
    zoomScale = 1,
    vectors = [],
    zoomObject = d3.zoomIdentity;

// d3 objects definitions
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
    .scaleExtent([0.1, 100000])   // TODO: better specification
    //.translateExtent([[0,0],[width,height]])
    .on("zoom", zoomed);
          
var svg = d3.select("body").append("svg")
    .attr("width", width)
    .attr("height", height);

var container = svg.append("g")
    .attr("id","cont")
    //.attr("transform", "translate("+(margin.left)+","+(margin.top)+")")
    .call(zoom);
        
var defs = svg.append("svg:defs");
defs.append("svg:marker")
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
defs.append("svg:marker")
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
defs.append("svg:marker")
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
defs.append("svg:marker")
		.attr("id", "reachArrow")
		.attr("viewBox", "0 "+(-0.5*arrowlen)+" "+arrowlen+" "+arrowlen)
		.attr("refX", 0.5*arrowlen)
		.attr("refY", 0)
		.attr("markerWidth", arrowlen)
		.attr("markerHeight", arrowlen)
		.attr("orient","auto")
    .append("svg:path")
      .attr("fill", reachColor)
			.attr("d", "M0,"+(-0.5*arrowlen)+" L"+arrowlen+",0 L0,"+(0.5*arrowlen))
			.attr("class","reachArrowHead");

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

generateGrid();
draw();
    
// ################# definitions of functions #################
    
function generateGrid() {
  vectors = [];
  
  var xmin = zoomObject.rescaleX(xScale).domain()[0],
      xmax = zoomObject.rescaleX(xScale).domain()[1],
      ymin = zoomObject.rescaleY(yScale).domain()[0],
      ymax = zoomObject.rescaleY(yScale).domain()[1],
      xp = d3.range(xmin,xmax,(xmax-xmin)/gridSize),
      yp = d3.range(ymin,ymax,(ymax-ymin)/gridSize);
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
        else vars[val] = Number(d3.select("#slider_"+val).property("value"));
      }
      var diffs = {};
      for (const [key, eq] of Object.entries(window.bio.eqs)) {
        diffs[key] = Number(eq(vars, params));
      }
      var direction = (color_style == "both" ? diffs[xDim]+diffs[yDim] : (color_style == "vertical" ? diffs[yDim] : (color_style == "horizontal" ? diffs[xDim] : 0)));
      vectors.push({
        id: i*xp.length+j,
        x0: zoomObject.rescaleX(xScale)(xp[j]),
        y0: zoomObject.rescaleY(yScale)(yp[i]),
        x1: zoomObject.rescaleX(xScale)(xp[j]+diffs[xDim]*dt),
        y1: zoomObject.rescaleY(yScale)(yp[i]+diffs[yDim]*dt),
        head:  (direction > Number(color_thr) ? "url(#positiveArrow)" : (direction < -Number(color_thr) ? "url(#negativeArrow)" : "url(#neutralArrow)")),
        color: (direction > Number(color_thr) ? positive_col : (direction < -Number(color_thr) ? negative_col : neutral_col)),
      });
    }
  }
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
  // reset brushes
  gBX.call(brushX.move, null);
  gBY.call(brushY.move, null);
}
function resettedReach() {
  reach_start = null; 
  reach_end = null; 
  trajectory_length = 1000; 
  d3.select("#trajectory").remove();
}
function resettedZoom() {
  update_axes()
  container.transition()
      .duration(500)
      .call(zoom.transform, d3.zoomIdentity);
}
function zoomed() {
  if(d3.event.transform) zoomObject = d3.event.transform;
  zoomScale = zoomObject.k;
  //console.log(zoomScale);
 
  generateGrid();
  draw();
  if(reach_start !== null) reach(null);
  
  gX.call(xAxis.scale(zoomObject.rescaleX(xScale)));
  gY.call(yAxis.scale(zoomObject.rescaleY(yScale)));
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
  //console.log((d3.max(thrs[xDim],parseFloat)-d3.min(thrs[xDim],parseFloat))/(domain[1]-domain[0]));
  //if((d3.max(thrs[xDim],parseFloat)-d3.min(thrs[xDim],parseFloat))/(domain[1]-domain[0]) > 100000) return;
  
  xScale = d3.scaleLinear()
              .domain(domain)
              .range([margin.left, width - margin.right]);
  zoomed()
}
function brushedY() {
  if (!d3.event.sourceEvent) return; // Only transition after input.
  if (!d3.event.selection) return; // Ignore empty selections.
  var sel = d3.event.selection;
  var domain = sel.map(yAxis.scale().invert);
  
  yScale = d3.scaleLinear()
              .domain(domain.reverse())
              .range([height - margin.bottom, margin.top]);
  zoomed()
}
function handleMouseOver(d, i) {
  var div = document.getElementById("infoPanel");
  var mouse = d3.mouse(this),
      vars = {};
  // fill variables with values of mouse position and sliders
  for(var v = 0; v < window.bio.vars.length; v++) {
    var key = window.bio.vars[v];
    if(key == xDim)       vars[key] = zoomObject.rescaleX(xScale).invert(mouse[0]);
    else if(key == yDim)  vars[key] = zoomObject.rescaleY(yScale).invert(mouse[1]);
    else                  vars[key] = Number(d3.select("#slider_"+key).property("value"));
  }
  // compute derivatives with current values of parameters and variables
  var diffs = {};
  for (const [key, eq] of Object.entries(window.bio.eqs)) {
    diffs[key] = Number(eq(vars, params));
  }
  
  var content = "Route start: "+(reach_start !== null ? ""+parsing_to_string(reach_start)+"" : "none");
  content +=  "\nRoute end:   "+(reach_end !== null ? ""+parsing_to_string(reach_end)+"" : "none");
  for(var v = 0; v < window.bio.vars.length; v++) {
    var key = window.bio.vars[v];
    content += "\n"+key+": "+(vars[key].toFixed(3))+"\td["+key+"]: "+(diffs[key].toFixed(3));
  }
  div.value = content;
}
function handleMouseOut(d, i) {
  var div = document.getElementById("infoPanel");
  var content = "Route start: "+(reach_start !== null ? ""+parsing_to_string(reach_start)+"" : "none");
  content +=  "\nRoute end:   "+(reach_end !== null ? ""+parsing_to_string(reach_end)+"" : "none");
  for(var v = 0; v < window.bio.vars.length; v++) {
    var key = window.bio.vars[v];
    var value = key == xDim ? zoomObject.rescaleX(xScale).domain() : (key == yDim ? zoomObject.rescaleY(yScale).domain() : Number(d3.select("#slider_"+key).property("value")) );
    content += "\n"+key+": "+(key == xDim || key == yDim ? ("["+(+value[0].toFixed(3))+", "+(+value[1].toFixed(3))+"]") : (+value.toFixed(3)));
  }
  div.value = content;
}
function elongate() {
  d3.select("#trajectory").remove();
  var vars = Object.assign({}, reach_end);
  
  var length = 500;
  for(var tp = 0; tp < length; tp++) {
    // compute derivatives with current values of parameters and variables
    var diffs = {};
    for (const [key, eq] of Object.entries(window.bio.eqs)) {
      diffs[key] = Number(eq(vars, params));
    }
    for (const [key, val] of Object.entries(diffs)) 
      vars[key] += val*traj_dt;
    trajectory += "L"+zoomObject.rescaleX(xScale)(vars[xDim])+","+zoomObject.rescaleY(yScale)(vars[yDim])+" ";
  }
  reach_end = Object.assign({}, vars);
  trajectory_length += length;
  container.append("path")
      .attr("id", "trajectory")
      .attr("class", "vector")
      .attr("stroke", reachColor)
      .attr("stroke-width", selfloopWidth)
      .attr("marker-end", "url(#reachArrow)")
      .attr("d", trajectory);
  d3.select("#zoomField").moveUp();
}
// counts trajectory in VF from selected origin point
function reach(event) {
  if(event !== null) {
      // this part is for clean new trajectory after mouse-click event
      reach_start = {};
      reach_end = null;
      trajectory_length = 1000;
      d3.select("#trajectory").remove();
      // fill variables with values of mouse position and sliders
      for(var v = 0; v < window.bio.vars.length; v++) {
        var key = window.bio.vars[v];
        if(key == xDim)       reach_start[key] = zoomObject.rescaleX(xScale).invert(event[0]);
        else if(key == yDim)  reach_start[key] = zoomObject.rescaleY(yScale).invert(event[1]);
        else                  reach_start[key] = Number(d3.select("#slider_"+key).property("value"));
      }
  }
  var vars = Object.assign({}, reach_start);
  trajectory = "M"+zoomObject.rescaleX(xScale)(vars[xDim])+","+zoomObject.rescaleY(yScale)(vars[yDim])+" ";
  
  var length = trajectory_length;
  for(var tp = 0; tp < length; tp++) {
    // compute derivatives with current values of parameters and variables
    var diffs = {};
    for (const [key, eq] of Object.entries(window.bio.eqs)) {
      diffs[key] = Number(eq(vars, params));
    }
    for (const [key, val] of Object.entries(diffs)) 
      vars[key] += val*traj_dt;
    trajectory += "L"+zoomObject.rescaleX(xScale)(vars[xDim])+","+zoomObject.rescaleY(yScale)(vars[yDim])+" ";
  }
  reach_end = Object.assign({}, vars);
  container.append("path")
      .attr("id", "trajectory")
      .attr("class", "vector")
      .attr("stroke", reachColor)
      .attr("stroke-width", selfloopWidth)
      .attr("marker-end", "url(#reachArrow)")
      .attr("d", trajectory);
  d3.select("#zoomField").moveUp();
}
// function for in-field mouse-click event (counts trajectory in VF)
function handleMouseClick(d, i) {
  console.log("heja");
  reach(d3.mouse(this));
}

function draw() {
  container.selectAll(".vector").remove();
  container.select("#zoomField").remove();
  
  container.selectAll(".vector")
    .data(vectors)
    .enter()
    .append("path")
    .attr("id", d => d.id)
    .attr("class", "vector")
    .attr("marker-end", d => d.head)
    .attr("stroke", d => d.color)
    .attr("stroke-width", transWidth)
    .attr("d", d => "M"+(d.x0)+" "+(d.y0)+" L"+(d.x1)+" "+(d.y1)+" ");
      
    
  container.append("rect")
    .attr("id", "zoomField")
    .attr("x", margin.left)
    .attr("y", margin.top)
    .attr("width", width-margin.right-margin.left)
    .attr("height", height-margin.bottom-margin.top)
    .attr("fill", "none")
    .on("click", handleMouseClick)
    .on("mousemove", handleMouseOver)
    .on("mouseout", handleMouseOut);
}

    </script>
  </body>

</html>
