shader_type spatial;
render_mode depth_test_disable, depth_draw_never, unshaded, cull_disabled;


uniform int SAMPLES : hint_range(8, 128);

//tweak these to your liking
uniform float indirectamount : hint_range(0.0, 512.0);
uniform float noiseamount : hint_range(0.0, 5.0);

uniform bool noise = true;

vec2 mod_dither3(vec2 u) {
	float noiseX = mod(u.x + u.y + mod(208. + u.x * 3.58, 13. + mod(u.y * 22.9, 9.)),7.) * .143;
	float noiseY = mod(u.y + u.x + mod(203. + u.y * 3.18, 12. + mod(u.x * 27.4, 8.)),6.) * .139;
	return vec2(noiseX, noiseY)*2.0-1.0;
}

vec2 dither(vec2 coord, float seed, vec2 size) {
	float noiseX = ((fract(1.0-(coord.x+seed*1.0)*(size.x/2.0))*0.25)+(fract((coord.y+seed*2.0)*(size.y/2.0))*0.75))*2.0-1.0;
	float noiseY = ((fract(1.0-(coord.x+seed*3.0)*(size.x/2.0))*0.75)+(fract((coord.y+seed*4.0)*(size.y/2.0))*0.25))*2.0-1.0;
    return vec2(noiseX, noiseY);
}


vec3 getViewPos(sampler2D tex, vec2 coord, mat4 ipm){
	float depth = texture(tex, coord).r;
	
	//Turn the current pixel from ndc to world coordinates
	vec3 pixel_pos_ndc = vec3(coord*2.0-1.0, depth*2.0-1.0); 
    vec4 pixel_pos_clip = ipm * vec4(pixel_pos_ndc,1.0);
    vec3 pixel_pos_cam = pixel_pos_clip.xyz / pixel_pos_clip.w;
	return pixel_pos_cam;
}


vec3 getViewNormal(sampler2D tex, vec2 coord, mat4 ipm)
{
    ivec2 texSize = textureSize(tex, 0);

    float pW = 1.0/float(texSize.x);
    float pH = 1.0/float(texSize.y);
    
    vec3 p1 = getViewPos(tex, coord+vec2(pW,0.0), ipm).xyz;
    vec3 p2 = getViewPos(tex, coord+vec2(0.0,pH), ipm).xyz;
    vec3 p3 = getViewPos(tex, coord+vec2(-pW,0.0), ipm).xyz;
    vec3 p4 = getViewPos(tex, coord+vec2(0.0,-pH), ipm).xyz;

    vec3 vP = getViewPos(tex, coord, ipm);
    
    vec3 dx = vP-p1;
    vec3 dy = p2-vP;
    vec3 dx2 = p3-vP;
    vec3 dy2 = vP-p4;
    
    if(length(dx2)<length(dx)&&coord.x-pW>=0.0||coord.x+pW>1.0) {
    dx = dx2;
    }
    if(length(dy2)<length(dy)&&coord.y-pH>=0.0||coord.y+pH>1.0) {
    dy = dy2;
    }
    
    return normalize(-cross( dx , dy ).xyz);
}

float lenSq(vec3 vector){
    return pow(vector.x, 2.0) + pow(vector.y, 2.0) + pow(vector.z, 2.0);
}

vec3 lightSample(sampler2D color_tex, sampler2D depth_tex,  vec2 coord, mat4 ipm, vec2 lightcoord, vec3 normal, vec3 position, float n, vec2 texsize){

	vec2 random = vec2(1.0);
	if (noise){
    	random = (mod_dither3((coord*texsize)+vec2(n*82.294,n*127.721)))*0.01*noiseamount;
	}else{
		random = dither(coord, 1.0, texsize)*0.1*noiseamount;
	}
    lightcoord *= vec2(0.7);
    
    //light absolute data
    vec3 lightcolor = textureLod(color_tex, ((lightcoord)+random),4.0).rgb;
    vec3 lightnormal   = getViewNormal(depth_tex, fract(lightcoord)+random, ipm).rgb;
    vec3 lightposition = getViewPos(depth_tex, fract(lightcoord)+random, ipm).xyz;

    
    //light variable data
    vec3 lightpath = lightposition - position;
    vec3 lightdir  = normalize(lightpath);
    
    //falloff calculations
    float cosemit  = clamp(dot(lightdir, -lightnormal), 0.0, 1.0); //emit only in one direction
    float coscatch = clamp(dot(lightdir, normal)*0.5+0.5,  0.0, 1.0); //recieve light from one direction
    float distfall = pow(lenSq(lightpath), 0.1) + 1.0;        //fall off with distance
    
    return (lightcolor * cosemit * coscatch / distfall)*(length(lightposition)/20.0);
}

void fragment()
{ 
	/*
	float depth = texture(DEPTH_TEXTURE, SCREEN_UV).r;
	
	//Turn the current pixel from ndc to world coordinates
	vec3 pixel_pos_ndc = vec3(SCREEN_UV*2.0-1.0, depth*2.0-1.0); 
    vec4 pixel_pos_clip = INV_PROJECTION_MATRIX * vec4(pixel_pos_ndc,1.0);
    vec3 pixel_pos_cam = pixel_pos_clip.xyz / pixel_pos_clip.w;
	vec3 pixel_pos_world = (inverse(INV_CAMERA_MATRIX) * vec4(pixel_pos_cam, 1.0)).xyz;
	
	//Calculate total velocity which combines linear velocity and angular velocity
	vec3 cam_pos = inverse(INV_CAMERA_MATRIX)[3].xyz; //Correct
	vec3 r = pixel_pos_world - cam_pos;
	vec3 total_velocity = linear_velocity + cross(angular_velocity, r);
	
	//Offset the world pos by the total velocity, then project back to ndc coordinates
	vec3 pixel_prevpos_world = pixel_pos_world - total_velocity;
	vec3 pixel_prevpos_cam =  ((INV_CAMERA_MATRIX) * vec4(pixel_prevpos_world, 1.0)).xyz;
	vec4 pixel_prevpos_clip =  PROJECTION_MATRIX * vec4(pixel_prevpos_cam, 1.0);
	vec3 pixel_prevpos_ndc = pixel_prevpos_clip.xyz / pixel_prevpos_clip.w;
	
	//Calculate how much the pixel moved in ndc space
	vec2 pixel_diff_ndc = pixel_prevpos_ndc.xy - pixel_pos_ndc.xy; 
	
	vec3 col = vec3(0.0);
	float counter = 0.0;
	for (int i = 0; i < iteration_count; i++)
	{
		vec2 offset = pixel_diff_ndc * (float(i) / float(iteration_count) - 0.5) * intensity; 
		col += textureLod(SCREEN_TEXTURE, SCREEN_UV + offset,0.0).rgb;
		counter++;
	}
	*/
	//ALBEDO = col / counter;
	
	//fragment color data
    vec3 direct = textureLod(SCREEN_TEXTURE,SCREEN_UV,0.0).rgb;
    vec3 color = normalize(direct).rgb;
    vec3 indirect = vec3(0.0,0.0,0.0);
    float PI = 3.14159;
    ivec2 iTexSize = textureSize(SCREEN_TEXTURE, 0);
    vec2 texSize = vec2(float(iTexSize.x),float(iTexSize.y));
    //fragment geometry data
    vec3 position = getViewPos(DEPTH_TEXTURE, SCREEN_UV, INV_PROJECTION_MATRIX);
    vec3 normal   = getViewNormal(DEPTH_TEXTURE, SCREEN_UV, INV_PROJECTION_MATRIX);
    
    //sampling in spiral
    
    float dlong = PI*(3.0-sqrt(5.0));
    float dz = 1.0/float(SAMPLES);
    float long = 0.0;
    float z = 1.0 - dz/2.0;
    
    
    for(int i = 0; i < SAMPLES; i++){
            
        float r = sqrt(1.0-z);
        
        float xpoint = (cos(long)*r)*0.5+0.5;
        float ypoint = (sin(long)*r)*0.5+0.5;
                
        z = z - dz;
        long = long + dlong;
    
        indirect += lightSample(SCREEN_TEXTURE, DEPTH_TEXTURE, SCREEN_UV, INV_PROJECTION_MATRIX, vec2(xpoint, ypoint), normal, position, float(i), texSize); 

        }

	
	ALBEDO = direct+(indirect/float(SAMPLES) * indirectamount);
}