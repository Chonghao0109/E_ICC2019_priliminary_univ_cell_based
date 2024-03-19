
`timescale 1ns/10ps

module  CONV(
	input									clk,
	input									reset,
	output reg						busy,	
	input									ready,	
			
	output reg 	[11:0] 		iaddr,
	input 			[19:0]		idata,	
	
	output reg 	 					cwr,
	output reg 	[11:0]	 	caddr_wr,
	output reg 	[19:0] 	 	cdata_wr,
	
	output reg	 					crd,
	output reg 	[11:0] 	 	caddr_rd,
	input	 			[19:0]		cdata_rd,
	
	output reg 	[2:0]			csel

);








	parameter signed BIAS = 20'h01310;
	parameter signed KERNEL_0 = 20'h0A89E;
	parameter signed KERNEL_1 = 20'h092D5;
	parameter signed KERNEL_2 = 20'h06D43;
	parameter signed KERNEL_3 = 20'h01004;
	parameter signed KERNEL_4 = 20'hF8F71;
	parameter signed KERNEL_5 = 20'hF6E54;
	parameter signed KERNEL_6 = 20'hFA6D7;
	parameter signed KERNEL_7 = 20'hFC834;
	parameter signed KERNEL_8 = 20'hFAC19;








	// Multiplier
	reg men;
	reg signed [19:0] ma,mb;
	wire mv;
	wire signed [39:0] mo ;

	//always@(posedge clk)begin
	//	if(men) begin
	//		mo = $signed(ma) * $signed(mb);
	//	end
	//end
	//assign mv = 1;

	multi_div
	#(
	  .SIZE_A(20),
	  .SIZE_B(20),
	  .SIGNED(1),
	  .STEP_SIZE(1) 
	)u_m1(
	  .clk(clk),
		.reset_n(!reset),
	  .en(men),
	  .select(1'b0),
	  .a(ma),
	  .b(mb),
	  .P(mo),
	  .div_zero(),
	  .Valid(mv),
	  .Busy()
	);












	reg signed [42:0] write_register;





	// FSM
	parameter IDLE								=	'd0;
	parameter CONV_READ_PIXEL			=	'd1;
	parameter WAIT_READ_DATA			= 'd2;
	parameter CALC_CONV						= 'd3;
	parameter CALC_RELU 					= 'd4;
	parameter	CONV_WRITE_PIXEL		= 'd5;
	parameter MAXPOOL_READ_PIXEL	= 'd6;
	parameter MAXPOOL_COMPARE			= 'd7;
	parameter MAXPOOL_WRITE_PIXEL	= 'd8; 
	parameter WAIT_WRITE					= 'd9; 

	reg [3:0] state, next_state;
	reg [5:0] state_x,state_y;
	reg [1:0] dx,dy ;
	
	always@(posedge clk or posedge reset) begin
		if(reset)begin
			busy <= 1'b0;
		end
		else begin
			if(state!=IDLE) busy <= 1'b1;
			else busy <= 1'b0;
		end
	end

	always @(posedge clk or posedge reset) begin : state_machine
		if(reset)begin
			state <= IDLE;
		end
		else begin
			state <= next_state;
		end
	end

	always@(*)begin : proc_next_state 
		case(state)
			
			IDLE:begin
				next_state = ready ? CONV_READ_PIXEL:IDLE;
			end

			CONV_READ_PIXEL:next_state = WAIT_READ_DATA;

			WAIT_READ_DATA:next_state = CALC_CONV;
			
			CALC_CONV:begin
				if(mv)begin
					if(dx==2 && dy==2) next_state = CALC_RELU;
					else next_state = CONV_READ_PIXEL;
				end
				else next_state = CALC_CONV;
			end
			CALC_RELU:begin
				next_state = CONV_WRITE_PIXEL;
			end
			CONV_WRITE_PIXEL:begin
				next_state = &{state_x,state_y} ? MAXPOOL_READ_PIXEL: CONV_READ_PIXEL;
			end
			MAXPOOL_READ_PIXEL:begin
				next_state = MAXPOOL_COMPARE;
			end
			MAXPOOL_COMPARE:begin
				next_state = (dx==1 && dy==1) ? MAXPOOL_WRITE_PIXEL:MAXPOOL_READ_PIXEL;
			end
			MAXPOOL_WRITE_PIXEL:begin
				next_state = &{state_x[4:0],state_y[4:0]} ? WAIT_WRITE: MAXPOOL_READ_PIXEL;
			end
			default:begin
				next_state = IDLE;
			end	
		endcase
	end






	always@(posedge clk or posedge reset)begin :proc_coordinate
		if(reset)begin
			state_x <= 0;
			state_y <= 0;
			dy <= 0;
			dx <= 0;
		end
		else begin
			case(state)
				
				
				IDLE:begin
					state_x <= 0;
					state_y <= 0;
					dy <= 0;
					dx <= 0;
				end



				CALC_CONV:begin
					if(mv)begin
						if(dy == 2 && dx == 2) {dy,dx} <= 0;
						else if(dx == 2) begin
							dy <= dy + 1;
							dx <= 0;
						end
						else dx <= dx + 1;
					end
				end

				CONV_WRITE_PIXEL:begin
					{state_y,state_x} <= {state_y,state_x} + 1;
				end


				MAXPOOL_COMPARE:begin
					if(dx==1)begin
						dy <= dy + 1;
						dx <= 0;
					end
					else dx <= dx + 1;
				end


				

				MAXPOOL_WRITE_PIXEL:begin
					if(state_x==31)begin
						state_y <= state_y + 1;
						state_x <= 0;
					end
					else state_x <= state_x+1;
					dx <= 0;
					dy <= 0;
				end


			endcase
		end
	end











	reg [19:0] idata_zp; 
	// Address Generator
	always @(posedge clk or posedge reset) begin :Memory_Controller
		if(reset) begin
			iaddr <= 0;
		end
		else begin
			if(state==CONV_READ_PIXEL)begin
				iaddr[11:6] <= state_y+dy-1;
				iaddr[5:0] <= state_x+dx-1;
				idata_zp <= 0;
			end
		end
	end
	

	always@(posedge clk or posedge reset)begin
		if(reset)begin
			csel <= 0;
			cwr <= 0;
			crd <= 0;
			caddr_rd <= 0;
			caddr_wr <= 0;
			cdata_wr <= 0;
		end 
		else begin
			case(state)
				CONV_WRITE_PIXEL:begin
					csel <= 1;
					cwr <= 1;
					crd <= 0;
					caddr_wr <= {state_y,state_x};
					cdata_wr <= (write_register[35:16]+write_register[15]);
				end
				MAXPOOL_READ_PIXEL:begin
					csel <= 1;
					cwr <= 0;
					crd <= 1;
					caddr_rd <= {state_y[4:0],dy[0],state_x[4:0],dx[0]};
					caddr_wr <= 0;
					cdata_wr <= 0;
				end
				MAXPOOL_WRITE_PIXEL:begin
					csel <= 3;
					cwr <= 1;
					crd <= 0;
					cdata_wr <= $unsigned(write_register); 
					caddr_wr <= {2'b00,state_y[4:0],state_x[4:0]};
				end
				default:begin
					csel <= 0;
					cwr <= 0;
					caddr_rd <= 0;
					caddr_wr <= 0;
					cdata_wr <= 0;
				end
			endcase
		end
	end





	always@(*)begin :Multiplier_Conroller
		case(state)
			WAIT_READ_DATA:begin
				if( (state_x+dx-1)<0 || (state_x+dx-1)>63 || (state_y+dy-1)<0 || (state_y+dy-1)>63) idata_zp = 0;
				else idata_zp = idata;
				ma = $signed({1'b0,idata_zp});
				if(dx==0 && dy ==0) mb = KERNEL_0;
				else if(dx==1 && dy ==0) mb = KERNEL_1;
				else if(dx==2 && dy ==0) mb = KERNEL_2;
				else if(dx==0 && dy ==1) mb = KERNEL_3;
				else if(dx==1 && dy ==1) mb = KERNEL_4;
				else if(dx==2 && dy ==1) mb = KERNEL_5;
				else if(dx==0 && dy ==2) mb = KERNEL_6;
				else if(dx==1 && dy ==2) mb = KERNEL_7;
				else if(dx==2 && dy ==2) mb = KERNEL_8;
				men = 1;
			end

			default:begin
				ma = 0;
				mb = 0;
				men = 0;
			end
		endcase
	end









	always@(posedge clk or posedge reset)begin : Data_Proccess
		if(reset)begin
			write_register <= {4'd00,BIAS<<16}; 
		end
		else begin
			case(state)
				IDLE:begin
					write_register <= {4'd0,BIAS,16'd0}; 
				end
				CALC_CONV:begin
					if(mv)begin
						write_register <= write_register + $signed(mo);
					end
				end
				CALC_RELU:begin
					if(write_register<0) write_register <= 0;
				end
				CONV_WRITE_PIXEL:begin
					write_register <= {4'd0,BIAS,16'd0}; 
				end
				MAXPOOL_COMPARE:begin
					if(dx==0 && dy ==0)begin
						write_register <= cdata_rd;
					end
					else if(write_register < cdata_rd)begin
						write_register <= cdata_rd;
					end
				end
			endcase
		end
	end



endmodule




